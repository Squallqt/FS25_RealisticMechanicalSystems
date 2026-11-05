-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Breakdown definitions.

RMS_Breakdowns.DASHBOARD = { ENGINE = "engine", WARNING = "warning", TRANSMISSION = "transmission", BRAKES = "brakes", BATTERY = "battery",
    COOLANT = "coolant", SERVICE = "service", OIL = "oil", PREHEAT = "preheat", TRACTION_BATTERY = "tractionBattery",
    LIMITED_POWER = "limitedPower", DPF = "dpf" }

-- speed gauge blue and orange, mixer wagon bad mix red
RMS_Breakdowns.COLORS = { DEFAULT = Dashboard.COLORS.GREY, COOL = { 0.0097, 0.4287, 0.6445, 1 }, WARNING = { 1, 0.4287, 0.0006, 1 },
    CRITICAL = { 0.8069, 0.0097, 0.0097, 1 } }

local color = RMS_Breakdowns.COLORS
local db = RMS_Breakdowns.DASHBOARD

-- the colour of several lamps sharing a slot is the highest of them
RMS_Breakdowns.COLOR_PRIORITY = { [color.DEFAULT] = 0, [color.COOL] = 1, [color.WARNING] = 2, [color.CRITICAL] = 3 }

local getIsElectricVehicle = RMS_Utils.getIsElectricVehicle
local hasCVTAddon = RMS_Utils.hasCVTAddon

local function isPowershiftBreakdownApplicable(vehicle)
    if hasCVTAddon(vehicle) or getIsElectricVehicle(vehicle) then return false end
    local motor = vehicle:getMotor()
    return motor ~= nil and (motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT)
end

-- the game shifts a truck's robotised gearbox like a powershift
local function isPowershiftClutchBreakdownApplicable(vehicle)
    return isPowershiftBreakdownApplicable(vehicle) and not vehicle.spec_RealisticMechanicalSystems.isTruck
end

local SKID_STEER_CATEGORIES = { SKIDSTEERVEHICLES = true }

---Tells whether a wheel runs inside a track
local function getIsTrackWheel(wheel)
    return wheel.physics ~= nil and wheel.physics.tireType == WheelsUtil.getTireType("crawler")
end

---Tells whether a tyre runs outside the tracks
local function getHasRoadWheel(vehicle)
    for _, wheel in ipairs(vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or {}) do
        if not getIsTrackWheel(wheel) then
            return true
        end
    end
    return false
end

---Tells whether one of those tyres steers
local function getHasSteeredRoadWheel(vehicle)
    for _, wheel in ipairs(vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or {}) do
        if not getIsTrackWheel(wheel) and RMS_Drivetrain.getIsWheelSteerable(wheel) then
            return true
        end
    end
    return false
end

---Tells whether the machine turns by bending at its central joint
local function getIsArticulated(vehicle)
    return vehicle.spec_articulatedAxis ~= nil and vehicle.spec_articulatedAxis.componentJoint ~= nil
end

---Tells whether a steering wheel turns the machine
local function getHasSteeringWheel(vehicle)
    return vehicle.spec_motorbike == nil and not RMS_Drivetrain.getIsInCategories(vehicle, SKID_STEER_CATEGORIES)
end

---Tells whether a steered axle carries knuckles and tie rods
local function isSteeredAxleBreakdownApplicable(vehicle)
    return getHasSteeringWheel(vehicle) and getHasSteeredRoadWheel(vehicle)
end

---Tells whether a hydraulic steering unit turns the machine
local function isSteeringUnitBreakdownApplicable(vehicle)
    return getHasSteeringWheel(vehicle) and (getHasSteeredRoadWheel(vehicle) or getIsArticulated(vehicle))
end

---Names the steering gear of a road vehicle, cylinder included
local function getSteeringGearVariant(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.isTruck then
        return "box"
    elseif RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        return "rack"
    end
    return nil
end

---Tells whether service brakes act on tyres or behind steered tracks
local function isServiceBrakeBreakdownApplicable(vehicle)
    return getHasRoadWheel(vehicle) or getIsArticulated(vehicle)
end

local function isCrawlerBreakdownApplicable(vehicle)
    return vehicle.spec_crawlers ~= nil and vehicle.spec_crawlers.crawlers ~= nil and #vehicle.spec_crawlers.crawlers > 0
end

-- the game also drives a sprayer's track width on the loader tool axis
---Names the arm a loader axis moves on a machine that is no loader
local function getLoaderVariant(vehicle)
    if RMS_Drivetrain.getIsInCategories(vehicle, { FORKLIFTS = true }) then
        return "mast"
    elseif RMS_Drivetrain.getIsInCategories(vehicle, { FORESTRYHARVESTERS = true, FORESTRYFORWARDERS = true }) then
        return "boom"
    elseif RMS_Drivetrain.getIsInCategories(vehicle, { FORAGEMIXERS = true }) then
        return "arm"
    elseif vehicle.spec_leveler ~= nil then
        return "blade"
    end
    return nil
end

local function isFrontLoaderPivotBreakdownApplicable(vehicle)
    local spec = vehicle.spec_cylindered
    for _, tool in ipairs(spec ~= nil and spec.movingTools or {}) do
        if tool.axis == "AXIS_FRONTLOADER_ARM" then
            return true
        end
    end
    return false
end

---Tells whether a differential splits the drive between two wheels
local function isWheelDifferentialBreakdownApplicable(vehicle)
    local motorized = vehicle.spec_motorized
    if vehicle.spec_motorbike ~= nil or motorized == nil or motorized.differentials == nil then
        return false
    end
    for _, differential in ipairs(motorized.differentials) do
        if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then
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
            or jointType == AttacherJoints.JOINTTYPE_TRAILERLOW
            or jointType == AttacherJoints.JOINTTYPE_SEMITRAILER then
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
    HEADER_LIFT_VALVE = "rms_breakdowns_part_header_lift_valve",
    HEADER_HEIGHT_SENSOR = "rms_breakdowns_part_header_height_sensor",
    LOADER_CONTROL = "rms_breakdowns_part_loader_control",
    MAST_CONTROL = "rms_breakdowns_part_mast_control",
    BOOM_CONTROL = "rms_breakdowns_part_boom_control",
    MILLING_ARM_CONTROL = "rms_breakdowns_part_milling_arm_control",
    BLADE_ARM_CONTROL = "rms_breakdowns_part_blade_arm_control",
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
    STEERING_BOX = "rms_breakdowns_part_steering_box",
    STEERING_RACK = "rms_breakdowns_part_steering_rack",
    CAB_SUSPENSION = "rms_breakdowns_part_cab_suspension",
    LOADER_PINS_AND_BUSHINGS = "rms_breakdowns_part_loader_pins_and_bushings",
    MAST_PINS_AND_BUSHINGS = "rms_breakdowns_part_mast_pins_and_bushings",
    BOOM_PINS_AND_BUSHINGS = "rms_breakdowns_part_boom_pins_and_bushings",
    MILLING_ARM_PINS_AND_BUSHINGS = "rms_breakdowns_part_milling_arm_pins_and_bushings",
    BLADE_ARM_PINS_AND_BUSHINGS = "rms_breakdowns_part_blade_arm_pins_and_bushings",
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
    SPARK_PLUGS = "rms_breakdowns_part_spark_plugs",
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
    FRONT_PTO_CLUTCH = "rms_breakdowns_part_front_pto_clutch",
    HARVEST_DRIVE_BELTS = "rms_breakdowns_part_harvest_drive_belts",
    HARVEST_DRIVE_BEARINGS = "rms_breakdowns_part_harvest_drive_bearings",
    FEEDER_CHAIN = "rms_breakdowns_part_feeder_chain",
    FEED_ACCELERATOR = "rms_breakdowns_part_feed_accelerator",
    THRESHING_BARS = "rms_breakdowns_part_threshing_bars",
    CONCAVE = "rms_breakdowns_part_concave",
    SEPARATION = "rms_breakdowns_part_separation",
    CLEANING_SIEVES = "rms_breakdowns_part_cleaning_sieves",
    GRAIN_ELEVATORS = "rms_breakdowns_part_grain_elevators",
    STRAW_CHOPPER = "rms_breakdowns_part_straw_chopper",
    FEED_ROLLS = "rms_breakdowns_part_feed_rolls",
    METAL_DETECTOR = "rms_breakdowns_part_metal_detector",
    CUTTERHEAD = "rms_breakdowns_part_cutterhead",
    FORAGE_KNIVES = "rms_breakdowns_part_forage_knives",
    SHEAR_BAR = "rms_breakdowns_part_shear_bar",
    CROP_PROCESSOR = "rms_breakdowns_part_crop_processor",
    CROP_ACCELERATOR = "rms_breakdowns_part_crop_accelerator",
    DISCHARGE_SPOUT = "rms_breakdowns_part_discharge_spout",
    BEET_TOPPER = "rms_breakdowns_part_beet_topper",
    LIFTING_SHARES = "rms_breakdowns_part_lifting_shares",
    BEET_CLEANING = "rms_breakdowns_part_beet_cleaning",
    ROOT_ELEVATOR = "rms_breakdowns_part_root_elevator",
    HOPPER_FLOOR = "rms_breakdowns_part_hopper_floor",
    SIEVE_WEBS = "rms_breakdowns_part_sieve_webs",
    HAULM_SEPARATOR = "rms_breakdowns_part_haulm_separator",
    PICKING_UNITS = "rms_breakdowns_part_picking_units",
    SPINDLE_MOISTENER = "rms_breakdowns_part_spindle_moistener",
    COTTON_FAN = "rms_breakdowns_part_cotton_fan",
    MODULE_BUILDER = "rms_breakdowns_part_module_builder",
    BASE_CUTTERS = "rms_breakdowns_part_base_cutters",
    CANE_FEED_ROLLS = "rms_breakdowns_part_cane_feed_rolls",
    CANE_CHOPPER = "rms_breakdowns_part_cane_chopper",
    CANE_EXTRACTOR = "rms_breakdowns_part_cane_extractor",
    CANE_ELEVATOR = "rms_breakdowns_part_cane_elevator",
    SHAKER = "rms_breakdowns_part_shaker",
    CATCHING_SCALES = "rms_breakdowns_part_catching_scales",
    BUCKET_CONVEYORS = "rms_breakdowns_part_bucket_conveyors",
    CLEANING_FANS = "rms_breakdowns_part_cleaning_fans",
    DESTEMMER = "rms_breakdowns_part_destemmer",
    VEGETABLE_PICKER = "rms_breakdowns_part_vegetable_picker",
    VEGETABLE_CLEANING = "rms_breakdowns_part_vegetable_cleaning",
    VEGETABLE_ELEVATORS = "rms_breakdowns_part_vegetable_elevators"
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
    SPARK_PLUG_WEAR = { 0.1167, 0.1167, 0.1167, 0.1167 },
    ADBLUE_PUMP_FAILURE = { 0.2912 },
    ADBLUE_DOSER_FAILURE = { 0.2182 },
    ADBLUE_FILTER_CLOGGING = { 0.02477, 0.02477, 0.02477, 0.02477 },
    NOX_SENSOR_FAILURE = { 0.1907 },
    PARTICULATE_FILTER_FAILURE = { 1.957, 1.957, 1.957, 1.957 },
    PARTICULATE_FILTER_SOOT_OVERLOAD = { 0.0, 0.1548 },
    TRACTION_BATTERY_CELL_FAULT = { 45.88, 45.88, 45.88, 45.88 },
    HV_CONTACTOR_FAILURE = { 0.3363, 0.3363, 0.3363, 0.3363 },
    HARVEST_DRIVE_BELT_WEAR = { 0.0185, 0.0185, 0.02774, 0.03699 },
    HARVEST_DRIVE_BEARING_WEAR = { 0.04624, 0.04624, 0.06936, 0.09248 },
    FEEDER_CHAIN_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    FEED_ACCELERATOR_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
    THRESHING_BAR_WEAR = { 0.7399, 0.7399, 1.11, 1.48 },
    CONCAVE_WEAR = { 0.4162, 0.4162, 0.6243, 0.8323 },
    SEPARATION_WEAR = { 0.2774, 0.2774, 0.4162, 0.5549 },
    CLEANING_SIEVE_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    GRAIN_ELEVATOR_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
    STRAW_CHOPPER_WEAR = { 0.3052, 0.3052, 0.4578, 0.6104 },
    FEED_ROLL_WEAR = { 0.05549, 0.05549, 0.08323, 0.111 },
    METAL_DETECTOR_FAILURE = { 0.09248, 0.09248, 0.09248 },
    CUTTERHEAD_WEAR = { 0.4624, 0.4624, 0.6936, 0.9248 },
    FORAGE_KNIFE_WEAR = { 0.3329, 0.3329, 0.4994, 0.6659 },
    SHEAR_BAR_WEAR = { 0.1572, 0.1572, 0.2358, 0.3144 },
    CROP_PROCESSOR_WEAR = { 0.8323, 0.8323, 1.249, 1.665 },
    CROP_ACCELERATOR_WEAR = { 0.09248, 0.09248, 0.1387, 0.185 },
    DISCHARGE_SPOUT_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
    BEET_TOPPER_WEAR = { 0.3052, 0.3052, 0.4578, 0.6104 },
    LIFTING_SHARE_WEAR = { 0.2774, 0.2774, 0.4162, 0.5549 },
    BEET_CLEANING_WEAR = { 0.4162, 0.4162, 0.6243, 0.8323 },
    ROOT_ELEVATOR_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    HOPPER_FLOOR_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
    SIEVE_WEB_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    HAULM_SEPARATOR_WEAR = { 0.4162, 0.4162, 0.6243, 0.8323 },
    PICKING_UNIT_WEAR = { 0.3329, 0.3329, 0.4994, 0.6659 },
    SPINDLE_MOISTENER_WEAR = { 0.0185, 0.0185, 0.02774, 0.03699 },
    COTTON_FAN_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    MODULE_BUILDER_WEAR = { 0.0185, 0.0185, 0.02774, 0.03699 },
    BASE_CUTTER_WEAR = { 0.3329, 0.3329, 0.4994, 0.6659 },
    CANE_FEED_ROLL_WEAR = { 0.05549, 0.05549, 0.08323, 0.111 },
    CANE_CHOPPER_WEAR = { 0.3329, 0.3329, 0.4994, 0.6659 },
    CANE_EXTRACTOR_WEAR = { 0.09248, 0.09248, 0.1387, 0.185 },
    CANE_ELEVATOR_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
    SHAKER_WEAR = { 0.7399, 0.7399, 1.11, 1.48 },
    CATCHING_SCALE_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
    BUCKET_CONVEYOR_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
    CLEANING_FAN_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    DESTEMMER_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    VEGETABLE_PICKER_WEAR = { 0.7399, 0.7399, 1.11, 1.48 },
    VEGETABLE_CLEANING_WEAR = { 0.185, 0.185, 0.2774, 0.3699 },
    VEGETABLE_ELEVATOR_WEAR = { 0.1387, 0.1387, 0.2081, 0.2774 },
}

local function isHydraulicBreakdownApplicable(vehicle)
    return RMS_Utils.hasHydraulicCapability(vehicle)
end

local function isHydraulicLiftBreakdownApplicable(vehicle)
    return isHydraulicBreakdownApplicable(vehicle) and RMS_Utils.hasHydraulicLiftCapability(vehicle)
end

-- the game lowers a car's tow hitch like a three-point lift
local function isHitchLiftBreakdownApplicable(vehicle)
    return isHydraulicLiftBreakdownApplicable(vehicle) and not RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
end

---Names a lift that only ever raises a harvesting header
local function getLiftVariant(vehicle)
    local carriesHeader = false
    for _, jointDesc in pairs(vehicle.spec_attacherJoints ~= nil and vehicle.spec_attacherJoints.attacherJoints or {}) do
        if RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
            if jointDesc.jointType ~= AttacherJoints.JOINTTYPE_CUTTER
                and jointDesc.jointType ~= AttacherJoints.JOINTTYPE_CUTTERHARVESTER then
                return nil
            end
            carriesHeader = true
        end
    end
    return carriesHeader and "header" or nil
end

local function isHydraulicHoseBreakdownApplicable(vehicle)
    return isHydraulicBreakdownApplicable(vehicle) and RMS_Utils.hasHydraulicHoseCapability(vehicle)
end

local function isHydraulicActuatorBreakdownApplicable(vehicle)
    return isHydraulicBreakdownApplicable(vehicle) and RMS_Utils.hasHydraulicControllableTargetCapability(vehicle)
end

local function isPtoBreakdownApplicable(vehicle)
    return RMS_Utils.hasPtoOutputCapability(vehicle)
end

local function isReducerBreakdownApplicable(vehicle)
    return getIsElectricVehicle(vehicle) and vehicle:getMotor().minForwardGearRatio ~= nil
end

local function isVariatorBreakdownApplicable(vehicle)
    return not hasCVTAddon(vehicle) and RMS_Utils.hasCVTTransmission(vehicle)
end

local function always() return true end
local function never() return false end
local function getHasEngine(vehicle) return not getIsElectricVehicle(vehicle) end
local function getHasEngineBelt(vehicle) return getHasEngine(vehicle) and vehicle.spec_motorbike == nil end
local function getHasParkBrake(vehicle) return vehicle.spec_motorbike == nil end
local function getHasEcu(vehicle) return RMS_Utils.getUsesEngineECUProfile(vehicle) end
local function getIsDiesel(vehicle) return RMS_Preheat.isDieselVehicle(vehicle) end
local function getHasDrivetrain(vehicle) return RMS_Drivetrain.getIsAvailable(vehicle) end
local function getHasThermalProtection(vehicle) return RMS_Thermal.getUsesEngineProtection(vehicle) end

local function getHasAirFilter(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec ~= nil and spec.isVehicleNeedBlowOut and not spec.isElectricVehicle
end

local function getHasTurbocharger(vehicle)
    return getHasEngineBelt(vehicle) and (vehicle:getMotor().peakMotorPower or 0) >= RMS_Config.CORE.TURBO_MIN_POWER_KW
end

local function getHasFanClutch(vehicle)
    local drive = RMS_Utils.getFanDrive(vehicle)
    return vehicle.spec_motorbike == nil and (drive == "VISCOUS" or drive == "ELECTRONIC")
end

local function getHasPowerDistribution(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.year >= 2000 and vehicle.spec_lights ~= nil
end

local function getHasParticulateFilter(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.hasParticulateFilter == true
end

local function getCarriesBulbs(circuit)
    return function(vehicle)
        return vehicle.spec_RealisticMechanicalSystems.year < RMS_Config.ELECTRICAL.LED_YEARS[circuit]
            and RMS_Breakdowns.getCarriesLightCircuit(vehicle, circuit)
    end
end

local function getIsCircuitLit(circuit)
    return function(vehicle) return RMS_Breakdowns.getIsLightCircuitLit(vehicle, circuit) end
end

local function getIsEngineRunning(vehicle)
    return vehicle ~= nil and vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()
end

local function getIsEngineStopped(vehicle) return not getIsEngineRunning(vehicle) end

local function getIsAtFullLoad(vehicle)
    return vehicle.spec_motorized ~= nil and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() > 0.95
end

local function getIsBelowHalfLoad(vehicle)
    return vehicle.spec_motorized ~= nil and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() <= 0.5
end

local function getBurnsFuel(vehicle, fillTypeName)
    local motorized = vehicle.spec_motorized
    return motorized ~= nil and motorized.consumersByFillTypeName ~= nil and motorized.consumersByFillTypeName[fillTypeName] ~= nil
end

local function getBurnsMethane(vehicle) return getBurnsFuel(vehicle, "METHANE") end
local function isAdBlueApplicable(vehicle) return getBurnsFuel(vehicle, "DEF") end
local function getHasDieselFuelSystem(vehicle) return getIsDiesel(vehicle) and not getBurnsMethane(vehicle) end
local function getHasCommonRail(vehicle) return getIsDiesel(vehicle) and getHasEcu(vehicle) end
local function getHasInjectionPump(vehicle) return getHasDieselFuelSystem(vehicle) and not getHasEcu(vehicle) end

-- an engine of unknown ECU profile keeps its high pressure pump
local function getHasHighPressurePump(vehicle)
    return getHasDieselFuelSystem(vehicle) and RMS_Utils.getUsesEngineECUProfile(vehicle) ~= false
end

local function getIsPowershift(motor)
    return motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
end

local function getHasGearbox(vehicle)
    return not hasCVTAddon(vehicle) and getHasEngine(vehicle) and vehicle:getMotor() ~= nil
end

local function getHasTransmissionPump(vehicle)
    local motor = getHasGearbox(vehicle) and vehicle:getMotor()
    return motor and (motor.minForwardGearRatio ~= nil or getIsPowershift(motor))
end

local function getHasShiftSensors(vehicle)
    local motor = getHasGearbox(vehicle) and getHasEcu(vehicle) and vehicle:getMotor()
    return motor and getIsPowershift(motor)
end

local function getHasClutchPedal(vehicle)
    local motor = not hasCVTAddon(vehicle) and not RMS_Drivetrain.getIsMachineCategory(vehicle) and vehicle:getMotor()
    return motor and motor.minForwardGearRatio == nil
end

local function getHasSynchronizers(vehicle)
    local motor = vehicle.spec_motorbike == nil and getHasClutchPedal(vehicle) and vehicle:getMotor()
    return motor and motor.gearType ~= VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
end

local function isVariatorSensorApplicable(vehicle)
    return isVariatorBreakdownApplicable(vehicle) and getHasEngine(vehicle) and getHasEcu(vehicle)
end

local function getHasFrontDrive(vehicle)
    return getHasDrivetrain(vehicle) and RMS_Drivetrain.getHasCenterDifferential(vehicle)
end

local function getHasLiftSensor(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return isHitchLiftBreakdownApplicable(vehicle) and spec.yearIsKnown == true and (tonumber(spec.year) or 0) >= 2000
end

local function getHasElectricPtoEngagement(vehicle)
    return isPtoBreakdownApplicable(vehicle) and (tonumber(vehicle.spec_RealisticMechanicalSystems.year) or 0) >= 1990
end

local function getHasPtoSpeedSensor(vehicle) return isPtoBreakdownApplicable(vehicle) and getHasEcu(vehicle) end
local function getHasFrontPto(vehicle) return isPtoBreakdownApplicable(vehicle) and RMS_Utils.getFrontPtoOutput(vehicle) ~= nil end

local function getHasSteeringCylinder(vehicle)
    return isSteeringUnitBreakdownApplicable(vehicle) and getSteeringGearVariant(vehicle) == nil
end

local function getIsRolling(vehicle) return vehicle:getLastSpeed() > 0.01 end
local function getIsMotorStarted(vehicle) return vehicle:getIsMotorStarted() end
local function getIsPtoTurning(vehicle) return vehicle.spec_RealisticMechanicalSystems.isPtoActive end
local function getIsFrontPtoTurning(vehicle) return RMS_Utils.getConnectedPtoData(vehicle, "front").isActive end

local function getIsLiftWorking(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec.isImplementLifted or spec.isHydraulicLiftMoving
end

local function getIsHydraulicsWorking(vehicle)
    return vehicle:getIsMotorStarted() and vehicle.spec_RealisticMechanicalSystems.isHydraulicActive
end

-- a part blocked in its second way passes no oil, so it wears no further
local function getWearsWhileFlowing(breakdownId)
    return function(vehicle)
        local breakdown = vehicle.spec_RealisticMechanicalSystems.activeBreakdowns[breakdownId]
        return (breakdown == nil or breakdown.branch ~= 2) and getIsHydraulicsWorking(vehicle)
    end
end

RMS_Breakdowns.BreakdownRegistry = {}

local MINOR = "rms_breakdowns_severity_minor"
local MODERATE = "rms_breakdowns_severity_moderate"
local MAJOR = "rms_breakdowns_severity_major"
local CRITICAL = "rms_breakdowns_severity_critical"
local PERMANENT = "rms_breakdowns_severity_permanent"
local REDUCED_POWER = "rms_breakdowns_severity_reduce_power"
local SHUTDOWN = "rms_breakdowns_severity_shutdown"
local SEVERITIES = { MINOR, MODERATE, MAJOR, CRITICAL }
-- share of the base progress time each stage lasts but the last
local STAGE_PROGRESS = { 2.0, 1.0, 0.5 }

-- how the same effect of several breakdowns adds up
local AGGREGATIONS = {}
for aggregation, effectIds in pairs({
    min = { "ALTERNATOR_HEALTH_MODIFIER", "BATTERY_HEALTH_MODIFIER", "BRAKE_FORCE_MODIFIER", "CAB_DAMPING_MODIFIER",
        "CHARGE_ACCEPTANCE_MODIFIER", "CVT_PRESSURE_DROP_CHANCE", "ENGINE_HESITATION_CHANCE", "ENGINE_LIMP_EFFECT",
        "ENGINE_STALLS_CHANCE", "ENGINE_THERMAL_TORQUE_LIMIT", "FAN_CLUTCH_MODIFIER", "FRONT_PTO_AUTO_DISENGAGE_CHANCE",
        "GEAR_REJECTION_CHANCE", "HARVEST_BLOCKAGE_CHANCE", "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", "HYDRAULIC_SPEED_MODIFIER",
        "LIGHTS_FLICKER_CHANCE", "LOADER_CONTROL_EFFECT", "PTO_AUTO_DISENGAGE_CHANCE", "RADIATOR_HEALTH_MODIFIER",
        "STARTER_HEALTH_MODIFIER", "THERMOSTAT_HEALTH_MODIFIER", "THERMOSTAT_STUCK_EFFECT", "TRAILER_BRAKE_FAILURE" },
    max = { "BELT_SQUEAL_NOISE_EFFECT", "BRAKE_PULL_EFFECT", "CAB_DAMPER_NOISE_EFFECT", "COOLANT_LEAK_RATE",
        "COOLANT_STEAM_NOISE_EFFECT", "CVT_MAX_RATIO_MODIFIER", "CVT_SLIP_EFFECT", "DRIVE_LOSS_EFFECT",
        "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", "ENGINE_HARD_START_MODIFIER",
        "ENGINE_KNOCKING_NOISE_EFFECT", "EXHAUST_OIL", "EXHAUST_SOOT", "EXHAUST_UNBURNT", "FAN_BLADE_NOISE_EFFECT",
        "FAN_CLUTCH_NOISE_EFFECT", "FRONT_AXLE_SHAFT_NOISE_EFFECT", "GAS_LEAK_NOISE_EFFECT", "GEARBOX_BEARING_NOISE_EFFECT",
        "GEAR_SHIFT_FAILURE_CHANCE", "GEAR_WHINE_NOISE_EFFECT", "GLOW_PLUG_COLD_IDLE_EFFECT", "GLOW_PLUG_FAILURE",
        "GLOW_PLUG_HARD_START_MODIFIER", "HARVEST_BEARING_NOISE_EFFECT", "HARVEST_THROUGHPUT_LIMIT",
        "HIGH_PRESSURE_PUMP_NOISE_EFFECT", "HOSE_BURST_NOISE_EFFECT", "HYDRAULIC_FLUID_LEAK_RATE",
        "HYDRAULIC_HOLD_DRIFT_EFFECT", "HYDRAULIC_PUMP_NOISE_EFFECT", "HYDROSTATIC_WHINE_NOISE_EFFECT", "IDLE_HUNTING_EFFECT",
        "INJECTOR_KNOCK_NOISE_EFFECT", "LOADER_PINS_NOISE_EFFECT", "MAX_SPEED_MODIFIER", "PARK_BRAKE_DRAG_EFFECT",
        "PARK_BRAKE_DRAG_NOISE_EFFECT", "PISTON_SLAP_NOISE_EFFECT", "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT",
        "PTO_BEARING_NOISE_EFFECT", "PTO_ENGAGEMENT_BLOCKED_CHANCE", "PTO_SHAFT_BREAK_NOISE_EFFECT", "PTO_SPLINES_NOISE_EFFECT",
        "PTO_STUCK_ENGAGED_CHANCE", "STEERING_KNUCKLE_NOISE_EFFECT", "STEERING_LINKAGE_NOISE_EFFECT",
        "STEERING_ORBITROL_NOISE_EFFECT", "STEERING_PLAY_EFFECT", "STEERING_STATIC_BIAS_EFFECT", "STEERING_WHEEL_FREE_EFFECT",
        "TRACK_CLATTER_NOISE_EFFECT", "TRACK_ROLLER_NOISE_EFFECT", "TRANSMISSION_OIL_LEAK_RATE",
        "TRANSMISSION_PUMP_NOISE_EFFECT", "TRANSMISSION_SLIP_EFFECT", "TURBO_WHISTLE_NOISE_EFFECT", "VALVE_TRAIN_NOISE_EFFECT",
        "WATER_PUMP_BEARING_NOISE_EFFECT", "WHEEL_HUB_BEARING_NOISE_EFFECT", "WHEEL_SEIZURE_EFFECT",
        "WHEEL_SEIZURE_GRIND_NOISE_EFFECT" },
    sum = { "CONDITION_WEAR_MODIFIER", "ELECTRICAL_LEAKAGE_EFFECT", "ENGINE_HEAT_MODIFIER", "ENGINE_TORQUE_MODIFIER",
        "FUEL_CONSUMPTION_MODIFIER", "HARVEST_GRAIN_LOSS", "HARVEST_POWER_DEMAND", "HYDRAULIC_HEAT_MODIFIER",
        "SERVICE_WEAR_MODIFIER", "TRACTION_BATTERY_CAPACITY_MODIFIER", "TRANSMISSION_HEAT_MODIFIER" },
    boolean_or = { "BEACON_LIGHTS_FAILURE", "CHOPPER_FAILURE", "DIFF_LOCK_ENGAGE_FAILURE", "DIFF_LOCK_STUCK_ENGAGED",
        "EMPTY_EFFECT", "ENGINE_FAILURE", "FOUR_WD_ENGAGE_FAILURE", "FOUR_WD_STUCK_ENGAGED", "FRONT_PTO_FAILURE",
        "FRONT_WORK_LIGHTS_FAILURE", "HARVEST_FAILURE", "HIGH_BEAM_FAILURE", "HYDRAULIC_FUNCTION_BLOCKED_EFFECT",
        "LIFT_CONTROL_FAILURE", "LIGHTS_FAILURE", "LOW_BEAM_FAILURE", "METAL_DETECTOR_OFF", "NOX_MONITORING_FAILURE",
        "PARTICULATE_FILTER_BLOCKED", "PTO_FAILURE", "REAR_WORK_LIGHTS_FAILURE", "SCR_DOSING_FAILURE",
        "SELF_DISAPPEARING_BREAKDOWN_EFFECT", "TURN_LIGHTS_FAILURE" }
}) do
    for _, effectId in ipairs(effectIds) do
        AGGREGATIONS[effectId] = aggregation
    end
end

-- extraData={starter, reason, disableAi, message}
local function stopEngine(extraData)
    local stop = { starter = false, reason = "BREAKDOWN", disableAi = true }
    for key, value in pairs(extraData or {}) do
        stop[key] = value
    end
    return { "ENGINE_FAILURE", 1.0, stop }
end

-- rms_breakdowns_<texts>[_<variant>][_branch<n>]_stage<i>_description
local function getStageText(texts, variant, branch, index)
    return string.format("rms_breakdowns_%s%s%s_stage%d_description", texts, variant ~= nil and "_" .. variant or "",
        branch ~= nil and "_branch" .. branch or "", index)
end

local function getBranchTexts(shape, variant, index)
    local texts = {}
    for branch = 1, shape.branches do
        texts[branch] = getStageText(shape.texts, variant, branch, index)
    end
    return texts
end

local function getHints(shape, index, which)
    local hints = {}
    for slot = 0, shape.branches or 0 do
        local texts = shape.hints[slot]
        if texts ~= nil and (which == true or which == slot) then
            local hint = { additional = string.format("rms_inspection_hint_%s_stage%d", texts, index), branch = slot > 0 and slot or nil }
            if shape.variantHints then
                hint.variantAdditional = {}
                for variant in pairs(shape.variantParts) do
                    hint.variantAdditional[variant] = string.format("rms_inspection_hint_%s_%s_stage%d", texts, variant, index)
                end
            end
            table.insert(hints, hint)
        end
    end
    return hints
end

-- declared={effect..., lamps={lamp...}, hint, stage overrides}
local function buildStage(id, shape, index, count, declared)
    local firstBranch = shape.branches ~= nil and 1 or nil
    local stage = {
        severity = declared.severity or SEVERITIES[index],
        description = declared.description or (shape.isSelectable and getStageText(shape.texts, nil, firstBranch, index) or ""),
        detectionChance = declared.detectionChance or (shape.isSelectable and 1.0 or 0.0),
        progressMultiplier = declared.progressMultiplier
            or ((shape.isSelectable and index < count) and STAGE_PROGRESS[index] * shape.progress or 0),
        repairPrice = stagePartPrices[id] ~= nil and stagePartPrices[id][index] or 0.0,
        renews = declared.renews,
        effects = {}
    }
    -- effect={effectId, value, extraData, branch=}
    for _, effect in ipairs(declared) do
        table.insert(stage.effects, { id = effect[1], value = effect[2], aggregation = AGGREGATIONS[effect[1]],
            extraData = effect[3] ~= nil and RMS_Utils.deepCopy(effect[3]) or nil, branch = effect.branch })
    end
    if declared.lamps ~= nil then
        stage.indicators = {}
        -- lamp={dashboard, color, switchOn, switchOff, branch=, blink=}
        for _, lamp in ipairs(declared.lamps) do
            table.insert(stage.indicators, { id = lamp[1], color = lamp[2], switchOn = lamp[3] or true, switchOff = lamp[4] or false,
                branch = lamp.branch, blinkWhileActive = lamp.blink })
        end
    end
    -- hint=true for the hint of each way, or the one way showing it
    if declared.hint ~= nil then
        stage.inspection = getHints(shape, index, declared.hint)
    end
    if shape.branches ~= nil and shape.isSelectable then
        stage.branchDescriptions = declared.branchDescriptions or getBranchTexts(shape, nil, index)
    end
    if shape.electric then
        stage.electricDescription = string.format("rms_breakdowns_%s_electric_stage%d_description", shape.texts, index)
    end
    if shape.variantParts ~= nil then
        stage.variantDescriptions = {}
        for variant in pairs(shape.variantParts) do
            stage.variantDescriptions[variant] = shape.branches ~= nil and getBranchTexts(shape, variant, index)
                or getStageText(shape.texts, variant, nil, index)
        end
    end
    return stage
end

-- a breakdown never reaches a system switched off on the machine
local function getIsApplicableInSystem(system, isApplicable)
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system)
    return function(vehicle)
        local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
        if spec == nil or spec.systems ~= nil and spec.systems[systemKey] ~= nil and spec.systems[systemKey].enabled == false then
            return false
        end
        return isApplicable(vehicle) == true
    end
end

-- def={texts, progress, hints, variantHints, electric, entry fields}
local function addBreakdown(id, def, stages)
    local entry = {
        isSelectable = def.isSelectable ~= false,
        system = def.system,
        part = def.part,
        isApplicable = def.system ~= nil and getIsApplicableInSystem(def.system, def.isApplicable) or def.isApplicable,
        isCanProgress = def.isCanProgress,
        causes = def.causes,
        component = def.component,
        branches = def.branches,
        getNameVariant = def.getNameVariant,
        variantParts = def.variantParts,
        wearsWhile = def.wearsWhile,
        wearsByCausesOnly = def.wearsByCausesOnly,
        stages = {}
    }
    local shape = {
        isSelectable = entry.isSelectable,
        texts = def.texts or string.lower(id),
        progress = def.progress or 1,
        branches = def.branches,
        electric = def.electric,
        variantParts = def.variantParts,
        -- hints[0] names the hint of a part failing a single way
        hints = type(def.hints) == "table" and def.hints or { [0] = def.hints or string.lower(id) },
        variantHints = def.variantHints
    }
    for index, declared in ipairs(stages) do
        entry.stages[index] = buildStage(id, shape, index, #stages, declared)
    end
    RMS_Breakdowns.BreakdownRegistry[id] = entry
end

addBreakdown("COLD_ENGINE", {
    isSelectable = false, system = systems.ENGINE, part = parts.ENGINE, isApplicable = getHasEngine, isCanProgress = never
}, {
    { { "ENGINE_HARD_START_MODIFIER", 0 }, severity = PERMANENT }
})

addBreakdown("DEAD_BATTERY", {
    isSelectable = false, system = systems.ELECTRICAL, part = parts.BATTERY, isApplicable = always, isCanProgress = never
}, {
    { stopEngine({ message = "rms_breakdowns_dead_battery_message" }), { "LIGHTS_FAILURE", 1.0 }, severity = PERMANENT,
        lamps = { { db.BATTERY, color.CRITICAL } } }
})

addBreakdown("VOLTAGE_SAG", {
    isSelectable = false, system = systems.ELECTRICAL, part = parts.VEHICLE, isApplicable = always, isCanProgress = never
}, {
    { { "LIGHTS_FLICKER_CHANCE", 0.1, { duration = 200, maskBackup = 0, status = "IDLE", timer = 0 } },
        { "PTO_AUTO_DISENGAGE_CHANCE", 1, { status = "IDLE" } }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HARD_START_MODIFIER", 3, { message = "rms_breakdowns_voltage_sag_message" } }, severity = PERMANENT,
        lamps = { { db.BATTERY, color.CRITICAL } } }
})

addBreakdown("COLD_TRACTION_BATTERY", {
    isSelectable = false, system = systems.FUEL, part = parts.TRACTION_BATTERY, isApplicable = getIsElectricVehicle,
        isCanProgress = never
}, {
    { { "FUEL_CONSUMPTION_MODIFIER", 0.1 }, { "ENGINE_TORQUE_MODIFIER", -0.05 }, severity = REDUCED_POWER },
    { { "FUEL_CONSUMPTION_MODIFIER", 0.25, { message = "rms_breakdowns_cold_traction_battery_message" } },
        { "ENGINE_TORQUE_MODIFIER", -0.1 }, severity = REDUCED_POWER,
        lamps = { { db.TRACTION_BATTERY, color.COOL }, { db.LIMITED_POWER, color.WARNING } } },
    { { "FUEL_CONSUMPTION_MODIFIER", 0.5, { message = "rms_breakdowns_cold_traction_battery_message" } },
        { "ENGINE_TORQUE_MODIFIER", -0.25 }, severity = REDUCED_POWER,
        lamps = { { db.TRACTION_BATTERY, color.COOL }, { db.LIMITED_POWER, color.WARNING } } },
    { { "FUEL_CONSUMPTION_MODIFIER", 1.0, { message = "rms_breakdowns_cold_traction_battery_message" } },
        { "ENGINE_TORQUE_MODIFIER", -0.4 }, severity = REDUCED_POWER,
        lamps = { { db.TRACTION_BATTERY, color.COOL }, { db.LIMITED_POWER, color.WARNING } } }
})

addBreakdown("AIRFILTER_CLOGGING", {
    isSelectable = false, system = systems.ENGINE, part = parts.VEHICLE, isApplicable = getHasAirFilter,
        isCanProgress = never
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.03 }, { "FUEL_CONSUMPTION_MODIFIER", 0.06 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.06 }, { "FUEL_CONSUMPTION_MODIFIER", 0.12 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "FUEL_CONSUMPTION_MODIFIER", 0.18 }, { "ENGINE_HEAT_MODIFIER", 0.05 } }
})

addBreakdown("STRESS_OVERLOAD", {
    isSelectable = false, part = parts.VEHICLE, isApplicable = always, isCanProgress = never
}, {
    { lamps = { { db.WARNING, color.WARNING } } },
    { { "EMPTY_EFFECT", 1.0, { reason = "BREAKDOWN" } }, severity = CRITICAL, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES", {
    isSelectable = false, part = parts.CONSUMABLES, isApplicable = always, isCanProgress = always
}, {
    { { "CONDITION_WEAR_MODIFIER", 0.33 }, { "SERVICE_WEAR_MODIFIER", 0.33 }, severity = "", progressMultiplier = 5.0 },
    { { "SELF_DISAPPEARING_BREAKDOWN_EFFECT", 1.0, { breakdownId = "MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES" } },
        severity = "" }
})

addBreakdown("ENGINE_THERMAL_PROTECTION", {
    isSelectable = false, system = systems.ENGINE, part = parts.VEHICLE, isApplicable = getHasThermalProtection,
        isCanProgress = never
}, {
    { { "ENGINE_THERMAL_TORQUE_LIMIT", 0.8, { message = "rms_breakdowns_overheat_protection_stage1_message", reason = "THERMAL_PROTECTION" } },
        severity = REDUCED_POWER, description = "rms_breakdowns_overheat_protection_stage1_description",
        lamps = { { db.WARNING, color.WARNING }, { db.LIMITED_POWER, color.WARNING } } },
    { { "ENGINE_THERMAL_TORQUE_LIMIT", 0.5, { message = "rms_breakdowns_overheat_protection_stage2_message", reason = "THERMAL_PROTECTION" } },
        severity = REDUCED_POWER, description = "rms_breakdowns_overheat_protection_stage2_description",
        lamps = { { db.WARNING, color.CRITICAL }, { db.LIMITED_POWER, color.WARNING } } }
})

addBreakdown("OVERHEAT_PROTECTION", {
    isSelectable = false, system = systems.ENGINE, part = parts.VEHICLE, isApplicable = always, isCanProgress = never
}, {
    { { "ENGINE_LIMP_EFFECT", -0.2, { disableAi = true, message = "rms_breakdowns_overheat_protection_stage1_message", reason = "OVERHEAT" } },
        severity = REDUCED_POWER, description = "rms_breakdowns_overheat_protection_stage1_description",
        lamps = { { db.WARNING, color.CRITICAL }, { db.LIMITED_POWER, color.WARNING } } },
    { { "ENGINE_LIMP_EFFECT", -0.5, { disableAi = true, message = "rms_breakdowns_overheat_protection_stage2_message", reason = "OVERHEAT" } },
        severity = REDUCED_POWER, description = "rms_breakdowns_overheat_protection_stage2_description",
        lamps = { { db.WARNING, color.CRITICAL }, { db.LIMITED_POWER, color.WARNING } } },
    { { "ENGINE_LIMP_EFFECT", -0.8, { disableAi = true, message = "rms_breakdowns_overheat_protection_stage3_message", reason = "OVERHEAT" } },
        severity = REDUCED_POWER, description = "rms_breakdowns_overheat_protection_stage3_description",
        lamps = { { db.WARNING, color.CRITICAL }, { db.LIMITED_POWER, color.WARNING } } },
    { stopEngine({ message = "rms_breakdowns_overheat_protection_stage4_message", reason = "OVERHEAT" }),
        severity = SHUTDOWN, description = "rms_breakdowns_overheat_protection_stage4_description",
        lamps = { { db.WARNING, color.CRITICAL }, { db.LIMITED_POWER, color.CRITICAL } } }
})

addBreakdown("ENGINE_JAM", {
    isSelectable = false, system = systems.ENGINE, part = parts.ENGINE, isApplicable = getHasEngine
}, {
    { stopEngine({ reason = "OVERHEAT" }), severity = CRITICAL,
        description = "rms_breakdowns_engine_jam_stage1_description", detectionChance = 1.0,
        lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("ECU_MALFUNCTION", {
    system = systems.ELECTRICAL, part = parts.ECU, isApplicable = getHasEcu,
        causes = { primary = { "ohf" }, secondary = { "vf" } }, component = "SOLID_STATE_CONTROLLER"
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "EXHAUST_SOOT", 0.25 },
        lamps = { { db.ENGINE, color.WARNING, getIsAtFullLoad, getIsBelowHalfLoad } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.2 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2 }, { "EXHAUST_SOOT", 0.45 },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.35 }, { "FUEL_CONSUMPTION_MODIFIER", 0.5 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HARD_START_MODIFIER", 2 }, { "EXHAUST_SOOT", 0.8 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("POWER_CABLE_CONNECTION_FAILURE", {
    system = systems.ELECTRICAL, part = parts.POWER_CABLES_AND_GROUNDS, isApplicable = getHasPowerDistribution,
        causes = { primary = { "wef", "vf" }, secondary = {} }, component = "ELECTRO_MECHANICAL", progress = 0.9,
        electric = true
}, {
    { { "LIGHTS_FLICKER_CHANCE", 1.0, { duration = 200, maskBackup = 0, status = "IDLE", timer = 0 } },
        { "ENGINE_HARD_START_MODIFIER", 3 }, { "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", 1 },
        { "ELECTRICAL_LEAKAGE_EFFECT", 1 } },
    { { "LIGHTS_FLICKER_CHANCE", 0.33, { duration = 300, maskBackup = 0, status = "IDLE", timer = 0 } },
        { "ENGINE_STALLS_CHANCE", 30.0 }, { "ENGINE_HARD_START_MODIFIER", 5 },
        { "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", 2 }, { "ELECTRICAL_LEAKAGE_EFFECT", 2 },
        lamps = { { db.BATTERY, color.WARNING } }, hint = true },
    { { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "LIGHTS_FAILURE", 1.0 }, { "ENGINE_STALLS_CHANCE", 20.0 },
        { "ENGINE_HARD_START_MODIFIER", 8 }, { "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", 4 },
        { "ELECTRICAL_LEAKAGE_EFFECT", 4 }, lamps = { { db.BATTERY, color.CRITICAL } }, hint = true },
    { { "LIGHTS_FAILURE", 1.0 }, { "ELECTRICAL_LEAKAGE_EFFECT", 8 }, stopEngine(),
        lamps = { { db.BATTERY, color.CRITICAL } }, hint = true }
})

addBreakdown("STARTER_RELAY_FAILURE", {
    system = systems.ELECTRICAL, part = parts.STARTER_RELAY, isApplicable = getHasEngine,
        causes = { primary = { "crf" }, secondary = {} }, component = "ELECTRO_MECHANICAL"
}, {
    { { "STARTER_HEALTH_MODIFIER", -1.0, { disableAi = true } }, { "ENGINE_HARD_START_MODIFIER", 1 }, severity = CRITICAL,
        lamps = { { db.ENGINE, color.WARNING } } }
})

addBreakdown("PREHEAT_RELAY_FAILURE", {
    system = systems.ELECTRICAL, part = parts.PREHEAT_RELAY, isApplicable = getIsDiesel,
        causes = { primary = { "crf" }, secondary = {} }, component = "ELECTRO_MECHANICAL"
}, {
    { { "GLOW_PLUG_FAILURE", 4 }, { "GLOW_PLUG_HARD_START_MODIFIER", 8, { blockStart = true } },
        { "GLOW_PLUG_COLD_IDLE_EFFECT", 0.1, { period = 1500, timer = 0 } }, severity = MAJOR,
        lamps = { { db.PREHEAT, color.WARNING, getIsEngineRunning, getIsEngineStopped, blink = true } } }
})

addBreakdown("LOW_BEAM_FAILURE", {
    system = systems.ELECTRICAL, part = parts.LOW_BEAM_BULBS, isApplicable = getCarriesBulbs("LOW_BEAM_FAILURE"),
        wearsWhile = getIsCircuitLit("LOW_BEAM_FAILURE"), causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H7"
}, {
    { { "LOW_BEAM_FAILURE", 1 }, severity = MAJOR }
})

addBreakdown("HIGH_BEAM_FAILURE", {
    system = systems.ELECTRICAL, part = parts.HIGH_BEAM_BULBS, isApplicable = getCarriesBulbs("HIGH_BEAM_FAILURE"),
        wearsWhile = getIsCircuitLit("HIGH_BEAM_FAILURE"), causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H7"
}, {
    { { "HIGH_BEAM_FAILURE", 1 }, severity = MAJOR }
})

addBreakdown("FRONT_WORK_LIGHTS_FAILURE", {
    system = systems.ELECTRICAL, part = parts.FRONT_WORK_LIGHT_BULBS,
        isApplicable = getCarriesBulbs("FRONT_WORK_LIGHTS_FAILURE"),
        wearsWhile = getIsCircuitLit("FRONT_WORK_LIGHTS_FAILURE"), causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H3"
}, {
    { { "FRONT_WORK_LIGHTS_FAILURE", 1 }, severity = MAJOR }
})

addBreakdown("REAR_WORK_LIGHTS_FAILURE", {
    system = systems.ELECTRICAL, part = parts.REAR_WORK_LIGHT_BULBS,
        isApplicable = getCarriesBulbs("REAR_WORK_LIGHTS_FAILURE"),
        wearsWhile = getIsCircuitLit("REAR_WORK_LIGHTS_FAILURE"), causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H3"
}, {
    { { "REAR_WORK_LIGHTS_FAILURE", 1 }, severity = MAJOR }
})

addBreakdown("BEACON_LIGHTS_FAILURE", {
    system = systems.ELECTRICAL, part = parts.BEACON_BULB, isApplicable = getCarriesBulbs("BEACON_LIGHTS_FAILURE"),
        wearsWhile = getIsCircuitLit("BEACON_LIGHTS_FAILURE"), causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H1"
}, {
    { { "BEACON_LIGHTS_FAILURE", 1 }, severity = MAJOR }
})

addBreakdown("TURN_LIGHTS_FAILURE", {
    system = systems.ELECTRICAL, part = parts.TURN_SIGNAL_BULBS, isApplicable = getCarriesBulbs("TURN_LIGHTS_FAILURE"),
        wearsWhile = getIsCircuitLit("TURN_LIGHTS_FAILURE"), causes = { primary = {}, secondary = {} }, component = "P21W"
}, {
    { { "TURN_LIGHTS_FAILURE", 1 }, severity = MAJOR }
})

addBreakdown("BATTERY_SULFATION", {
    system = systems.ELECTRICAL, part = parts.BATTERY, isApplicable = always,
        causes = { primary = { "crf" }, secondary = {} }, component = "STARTER_BATTERY", progress = 1.4, electric = true
}, {
    { { "BATTERY_HEALTH_MODIFIER", -0.3 } },
    { { "BATTERY_HEALTH_MODIFIER", -0.6 }, { "ENGINE_HARD_START_MODIFIER", 3 }, lamps = { { db.BATTERY, color.WARNING } } },
    { { "BATTERY_HEALTH_MODIFIER", -0.75 }, { "ENGINE_HARD_START_MODIFIER", 6 }, lamps = { { db.BATTERY, color.CRITICAL } } },
    { { "BATTERY_HEALTH_MODIFIER", -1.0 }, { "ENGINE_HARD_START_MODIFIER", 9 }, lamps = { { db.BATTERY, color.CRITICAL } } }
})

addBreakdown("GLOW_PLUG_FAILURE", {
    system = systems.ELECTRICAL, part = parts.GLOW_PLUGS, isApplicable = getIsDiesel,
        causes = { primary = { "crf" }, secondary = {} }, component = "ELECTRO_MECHANICAL"
}, {
    { { "GLOW_PLUG_FAILURE", 1 }, { "GLOW_PLUG_HARD_START_MODIFIER", 2 }, detectionChance = 0.5,
        lamps = { { db.PREHEAT, color.WARNING, getIsEngineRunning, getIsEngineStopped, blink = true } } },
    { { "GLOW_PLUG_FAILURE", 2 }, { "GLOW_PLUG_HARD_START_MODIFIER", 4 },
        { "GLOW_PLUG_COLD_IDLE_EFFECT", 0.05, { period = 1800, timer = 0 } }, detectionChance = 0.75,
        lamps = { { db.PREHEAT, color.WARNING, getIsEngineRunning, getIsEngineStopped, blink = true } } },
    { { "GLOW_PLUG_FAILURE", 3 }, { "GLOW_PLUG_HARD_START_MODIFIER", 8 },
        { "GLOW_PLUG_COLD_IDLE_EFFECT", 0.1, { period = 1500, timer = 0 } },
        lamps = { { db.PREHEAT, color.WARNING, getIsEngineRunning, getIsEngineStopped, blink = true } } },
    { { "GLOW_PLUG_FAILURE", 4 }, { "GLOW_PLUG_HARD_START_MODIFIER", 8, { blockStart = true } },
        { "GLOW_PLUG_COLD_IDLE_EFFECT", 0.1, { period = 1500, timer = 0 } },
        lamps = { { db.PREHEAT, color.WARNING, getIsEngineRunning, getIsEngineStopped, blink = true } } }
})

addBreakdown("ALTERNATOR", {
    system = systems.ELECTRICAL, part = parts.ALTERNATOR, isApplicable = getHasEngine,
        causes = { primary = { "ohf", "crf" }, secondary = { "ltf", "vf" } }, component = "SOLID_STATE_CONTROLLER",
        branches = 2, progress = 1.1, hints = { [1] = "alternator" }
}, {
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.2 }, { "ELECTRICAL_LEAKAGE_EFFECT", 1, branch = 2 } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.5 }, { "ELECTRICAL_LEAKAGE_EFFECT", 2, branch = 2 },
        lamps = { { db.BATTERY, color.WARNING } } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.7 }, { "ELECTRICAL_LEAKAGE_EFFECT", 4, branch = 2 },
        lamps = { { db.BATTERY, color.CRITICAL } }, hint = true },
    { { "ALTERNATOR_HEALTH_MODIFIER", -1.0 }, { "ELECTRICAL_LEAKAGE_EFFECT", 8, branch = 2 },
        lamps = { { db.BATTERY, color.CRITICAL } }, hint = true }
})

addBreakdown("STARTER_FAILURE", {
    system = systems.ELECTRICAL, part = parts.STARTER, isApplicable = getHasEngine,
        causes = { primary = { "crf" }, secondary = {} }, component = "DC_MOTOR", progress = 1.1
}, {
    { { "STARTER_HEALTH_MODIFIER", -0.2 }, { "ENGINE_HARD_START_MODIFIER", 1 } },
    { { "STARTER_HEALTH_MODIFIER", -0.4 }, { "ENGINE_HARD_START_MODIFIER", 1 } },
    { { "STARTER_HEALTH_MODIFIER", -0.55 }, { "ENGINE_HARD_START_MODIFIER", 1 } },
    { { "STARTER_HEALTH_MODIFIER", -1.0, { disableAi = true } }, { "ENGINE_HARD_START_MODIFIER", 1 } }
})

addBreakdown("INVERTER_MALFUNCTION", {
    system = systems.ELECTRICAL, part = parts.INVERTER, isApplicable = getIsElectricVehicle,
        causes = { primary = { "ohf" }, secondary = { "wef", "vf" } }, component = "SOLID_STATE_CONTROLLER"
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.1 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.2 }, { "FUEL_CONSUMPTION_MODIFIER", 0.1 }, lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.35 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine(), lamps = { { db.ENGINE, color.CRITICAL }, { db.WARNING, color.CRITICAL } } }
})

addBreakdown("DCDC_CONVERTER_FAILURE", {
    system = systems.ELECTRICAL, part = parts.DCDC_CONVERTER, isApplicable = getIsElectricVehicle,
        causes = { primary = { "ohf", "ltf" }, secondary = { "vf" } }, component = "SOLID_STATE_CONTROLLER", progress = 1.1
}, {
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.2 } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.5 }, lamps = { { db.BATTERY, color.WARNING } } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.7 }, lamps = { { db.BATTERY, color.CRITICAL } } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -1.0 }, lamps = { { db.BATTERY, color.CRITICAL } } }
})

addBreakdown("ONBOARD_CHARGER_FAILURE", {
    system = systems.ELECTRICAL, part = parts.ONBOARD_CHARGER, isApplicable = getIsElectricVehicle,
        causes = { primary = { "wef" }, secondary = {} }, component = "SOLID_STATE_CONTROLLER", progress = 1.1
}, {
    { { "CHARGE_ACCEPTANCE_MODIFIER", -0.35 } },
    { { "CHARGE_ACCEPTANCE_MODIFIER", -0.65 }, lamps = { { db.TRACTION_BATTERY, color.WARNING } } },
    { { "CHARGE_ACCEPTANCE_MODIFIER", -0.9 }, lamps = { { db.TRACTION_BATTERY, color.CRITICAL } } },
    { { "CHARGE_ACCEPTANCE_MODIFIER", -1.0 }, lamps = { { db.TRACTION_BATTERY, color.CRITICAL } } }
})

addBreakdown("HV_INSULATION_LOSS", {
    system = systems.ELECTRICAL, part = parts.HV_WIRING, isApplicable = getIsElectricVehicle,
        causes = { primary = { "wef" }, secondary = { "vf" } }, component = "TRANSFORMER", progress = 0.9
}, {
    { lamps = { { db.WARNING, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.15 }, lamps = { { db.WARNING, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_STALLS_CHANCE", 20.0 }, lamps = { { db.WARNING, color.CRITICAL } } },
    { stopEngine(), lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("TURBOCHARGER_MALFUNCTION", {
    system = systems.ENGINE, part = parts.TURBOCHARGER, isApplicable = getHasTurbocharger,
        causes = { primary = { "hmf", "mlf" }, secondary = { "aicf", "sf", "flf", "cmf" } },
        component = "CENTRIFUGAL_COMPRESSOR", texts = "turbocharger_wear", progress = 1.1
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "TURBO_WHISTLE_NOISE_EFFECT", 0.25 }, { "EXHAUST_SOOT", 0.2 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.25 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2 }, { "TURBO_WHISTLE_NOISE_EFFECT", 0.35 },
        { "EXHAUST_SOOT", 0.4 }, { "EXHAUST_OIL", 0.25 }, lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.35 }, { "FUEL_CONSUMPTION_MODIFIER", 0.4 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "TURBO_WHISTLE_NOISE_EFFECT", 0.6 }, { "EXHAUST_SOOT", 0.65 }, { "EXHAUST_OIL", 0.5 },
        lamps = { { db.ENGINE, color.CRITICAL } }, hint = true },
    { { "ENGINE_TORQUE_MODIFIER", -0.5 }, { "FUEL_CONSUMPTION_MODIFIER", 0.6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "EXHAUST_SOOT", 0.9 }, { "EXHAUST_OIL", 0.7 },
        lamps = { { db.ENGINE, color.CRITICAL }, { db.WARNING, color.CRITICAL } }, hint = true }
})

addBreakdown("OIL_PUMP_MALFUNCTION", {
    system = systems.ENGINE, part = parts.OIL_PUMP, isApplicable = getHasEngine,
        causes = { primary = { "sf" }, secondary = { "flf" } }, component = "LUBRICATOR_PUMP", progress = 1.3
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "ENGINE_KNOCKING_NOISE_EFFECT", 0.3 }, { "ENGINE_HEAT_MODIFIER", 0.05 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.25 }, { "ENGINE_KNOCKING_NOISE_EFFECT", 0.5 }, { "ENGINE_HEAT_MODIFIER", 0.15 },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.45 }, { "ENGINE_STALLS_CHANCE", 10.0 }, { "ENGINE_KNOCKING_NOISE_EFFECT", 0.8 },
        { "ENGINE_HEAT_MODIFIER", 0.35 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("PISTONS", {
    system = systems.ENGINE, part = parts.PISTONS, isApplicable = getHasEngine,
        causes = { primary = { "sf", "cmf", "hmf", "flf" }, secondary = { "mlf", "lf" } }, component = "ENGINE_PISTON",
        branches = 2, progress = 1.4
}, {
    { },
    { { "EXHAUST_OIL", 0.2 }, { "PISTON_SLAP_NOISE_EFFECT", 0.5 } },
    { { "EXHAUST_OIL", 0.4 }, { "ENGINE_TORQUE_MODIFIER", -0.12 }, { "ENGINE_HARD_START_MODIFIER", 3 },
        { "PISTON_SLAP_NOISE_EFFECT", 0.8 }, lamps = { { db.ENGINE, color.WARNING } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("PISTON_RINGS", {
    system = systems.ENGINE, part = parts.PISTON_RINGS, isApplicable = getHasEngine,
        causes = { primary = { "sf", "cmf", "hmf", "flf" }, secondary = { "mlf", "lf" } }, component = "ENGINE_PISTON",
        branches = 3, progress = 1.4
}, {
    { },
    { { "ENGINE_TORQUE_MODIFIER", -0.04, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 3, branch = 1 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.05, branch = 1 }, { "ENGINE_TORQUE_MODIFIER", -0.04, branch = 3 },
        { "ENGINE_HARD_START_MODIFIER", 3, branch = 3 }, { "FUEL_CONSUMPTION_MODIFIER", 0.05, branch = 3 },
        { "EXHAUST_OIL", 0.2, branch = 2 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.12, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 6, branch = 1 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.1, branch = 1 }, { "ENGINE_TORQUE_MODIFIER", -0.12, branch = 3 },
        { "ENGINE_HARD_START_MODIFIER", 6, branch = 3 }, { "FUEL_CONSUMPTION_MODIFIER", 0.1, branch = 3 },
        { "EXHAUST_OIL", 0.4, branch = 2 },
        lamps = { { db.ENGINE, color.WARNING, branch = 1 }, { db.ENGINE, color.WARNING, branch = 3 } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.25, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 9, branch = 1 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.2, branch = 1 }, { "ENGINE_TORQUE_MODIFIER", -0.25, branch = 3 },
        { "ENGINE_HARD_START_MODIFIER", 9, branch = 3 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2, branch = 3 },
        { "EXHAUST_OIL", 0.65, branch = 2 }, { "EXHAUST_OIL", 0.65, branch = 3 },
        lamps = { { db.ENGINE, color.CRITICAL, branch = 1 }, { db.ENGINE, color.CRITICAL, branch = 3 } } }
})

addBreakdown("CYLINDER_LINERS", {
    system = systems.ENGINE, part = parts.CYLINDER_LINERS, isApplicable = getHasEngine,
        causes = { primary = { "sf", "cmf", "hmf", "flf" }, secondary = { "mlf", "lf" } }, component = "CYLINDER_LINER",
        branches = 2, progress = 1.4, hints = { [2] = "cylinder_liners" }
}, {
    { },
    { { "EXHAUST_OIL", 0.25, branch = 1 }, { "ENGINE_TORQUE_MODIFIER", -0.04, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.08, branch = 2 }, { "PISTON_SLAP_NOISE_EFFECT", 0.5, branch = 1 }, hint = true },
    { { "EXHAUST_OIL", 0.5, branch = 1 }, { "ENGINE_TORQUE_MODIFIER", -0.12, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.25, branch = 2 }, { "EXHAUST_UNBURNT", 0.3, branch = 2 },
        { "PISTON_SLAP_NOISE_EFFECT", 0.8, branch = 1 },
        lamps = { { db.ENGINE, color.WARNING, branch = 1 }, { db.COOLANT, color.WARNING, branch = 2 } }, hint = true },
    { { "ENGINE_FAILURE", 1.0, { disableAi = true, reason = "BREAKDOWN", starter = true }, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.8, branch = 2 }, { "EXHAUST_UNBURNT", 0.5, branch = 2 },
        lamps = { { db.ENGINE, color.CRITICAL, branch = 1 }, { db.COOLANT, color.CRITICAL, branch = 2 } }, hint = true }
})

addBreakdown("INLET_VALVES", {
    system = systems.ENGINE, part = parts.INLET_VALVES, isApplicable = getHasEngine,
        causes = { primary = { "sf", "cmf" }, secondary = { "flf", "hmf", "mlf" } }, component = "ENGINE_VALVE",
        branches = 2, progress = 1.4
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.04 }, { "FUEL_CONSUMPTION_MODIFIER", 0.05 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.12 }, { "FUEL_CONSUMPTION_MODIFIER", 0.1 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.25 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2 },
        { "ENGINE_HESITATION_CHANCE", 0.15, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 } },
        { "ENGINE_STALLS_CHANCE", 10.0 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.25, branch = 1 },
        { "ENGINE_HESITATION_CHANCE", 0.15, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 }, branch = 1 },
        { "ENGINE_STALLS_CHANCE", 10.0, branch = 1 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2, branch = 1 },
        { "ENGINE_FAILURE", 1.0, { disableAi = true, reason = "BREAKDOWN", starter = true }, branch = 2 },
        lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("EXHAUST_VALVES", {
    system = systems.ENGINE, part = parts.EXHAUST_VALVES, isApplicable = getHasEngine,
        causes = { primary = { "sf", "cmf" }, secondary = { "flf", "hmf", "mlf" } }, component = "ENGINE_VALVE",
        branches = 2, progress = 1.4
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.04 }, { "FUEL_CONSUMPTION_MODIFIER", 0.05 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.12 }, { "FUEL_CONSUMPTION_MODIFIER", 0.1 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.25 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2 },
        { "ENGINE_HESITATION_CHANCE", 0.15, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 } },
        { "ENGINE_STALLS_CHANCE", 10.0 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.25, branch = 1 },
        { "ENGINE_HESITATION_CHANCE", 0.15, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 }, branch = 1 },
        { "ENGINE_STALLS_CHANCE", 10.0, branch = 1 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2, branch = 1 },
        { "ENGINE_FAILURE", 1.0, { disableAi = true, reason = "BREAKDOWN", starter = true }, branch = 2 },
        lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("VALVE_GUIDES_SEALS", {
    system = systems.ENGINE, part = parts.VALVE_GUIDES_SEALS, isApplicable = getHasEngine,
        causes = { primary = { "sf", "cmf" }, secondary = { "flf", "hmf", "mlf" } }, component = "ENGINE_VALVE",
        branches = 2, progress = 1.4
}, {
    { { "VALVE_TRAIN_NOISE_EFFECT", 0.5, branch = 1 }, { "EXHAUST_OIL", 0.2 } },
    { { "VALVE_TRAIN_NOISE_EFFECT", 0.7, branch = 1 }, { "EXHAUST_OIL", 0.4 } },
    { { "VALVE_TRAIN_NOISE_EFFECT", 1.0, branch = 1 }, { "EXHAUST_OIL", 0.65 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 }, branch = 1 },
        { "ENGINE_TORQUE_MODIFIER", -0.12, branch = 1 }, lamps = { { db.ENGINE, color.CRITICAL, branch = 1 } } },
    { { "VALVE_TRAIN_NOISE_EFFECT", 1.0, branch = 1 }, { "EXHAUST_OIL", 0.65 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 }, branch = 1 },
        { "ENGINE_TORQUE_MODIFIER", -0.12, branch = 1 }, lamps = { { db.ENGINE, color.CRITICAL, branch = 1 } } }
})

addBreakdown("CYLINDER_HEAD", {
    system = systems.ENGINE, part = parts.CYLINDER_HEAD, isApplicable = getHasEngine, wearsByCausesOnly = true,
        causes = { primary = { "hmf" }, secondary = {} }, component = "HEAT_EXCHANGER", branches = 3, progress = 1.4,
        hints = { [2] = "cylinder_head" }
}, {
    { },
    { { "ENGINE_TORQUE_MODIFIER", -0.04, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 3, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.08, branch = 1 }, { "COOLANT_LEAK_RATE", 0.08, branch = 2 },
        { "COOLANT_LEAK_RATE", 0.08, branch = 3 }, hint = true },
    { { "ENGINE_TORQUE_MODIFIER", -0.12, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 6, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.25, branch = 1 }, { "COOLANT_LEAK_RATE", 0.25, branch = 2 },
        { "COOLANT_LEAK_RATE", 0.25, branch = 3 }, { "EXHAUST_UNBURNT", 0.3, branch = 1 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.WARNING, branch = 2 }, { db.COOLANT, color.WARNING, branch = 3 } },
        hint = true },
    { { "ENGINE_TORQUE_MODIFIER", -0.25, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 9, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.8, branch = 1 }, { "COOLANT_LEAK_RATE", 0.8, branch = 2 },
        { "COOLANT_LEAK_RATE", 0.8, branch = 3 }, { "EXHAUST_UNBURNT", 0.5, branch = 1 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.CRITICAL, branch = 2 }, { db.COOLANT, color.CRITICAL, branch = 3 } },
        hint = true }
})

addBreakdown("CYLINDER_HEAD_GASKET", {
    system = systems.ENGINE, part = parts.CYLINDER_HEAD_GASKET, isApplicable = getHasEngine,
        causes = { primary = { "hmf" }, secondary = { "sf" } }, component = "ENGINE_HEAD_GASKET", branches = 3,
        progress = 1.4, hints = { [2] = "cylinder_head_gasket" }
}, {
    { },
    { { "ENGINE_TORQUE_MODIFIER", -0.04, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 3, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.08, branch = 1 }, { "COOLANT_LEAK_RATE", 0.08, branch = 2 },
        { "COOLANT_LEAK_RATE", 0.08, branch = 3 }, hint = true },
    { { "ENGINE_TORQUE_MODIFIER", -0.12, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 6, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.25, branch = 1 }, { "COOLANT_LEAK_RATE", 0.25, branch = 2 },
        { "COOLANT_LEAK_RATE", 0.25, branch = 3 }, { "EXHAUST_UNBURNT", 0.3, branch = 1 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.WARNING, branch = 2 }, { db.COOLANT, color.WARNING, branch = 3 } },
        hint = true },
    { { "ENGINE_TORQUE_MODIFIER", -0.25, branch = 1 }, { "ENGINE_HARD_START_MODIFIER", 9, branch = 1 },
        { "COOLANT_LEAK_RATE", 0.8, branch = 1 }, { "COOLANT_LEAK_RATE", 0.8, branch = 2 },
        { "COOLANT_LEAK_RATE", 0.8, branch = 3 }, { "EXHAUST_UNBURNT", 0.5, branch = 1 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.CRITICAL, branch = 2 }, { db.COOLANT, color.CRITICAL, branch = 3 } },
        hint = true }
})

addBreakdown("MAIN_BEARINGS", {
    system = systems.ENGINE, part = parts.MAIN_BEARINGS, isApplicable = getHasEngine,
        causes = { primary = { "flf", "hmf" }, secondary = { "sf", "mlf" } }, component = "SLEEVE_BEARING", branches = 2,
        progress = 1.4
}, {
    { },
    { },
    { { "ENGINE_KNOCKING_NOISE_EFFECT", 0.8 }, { "ENGINE_HEAT_MODIFIER", 0.35 }, lamps = { { db.OIL, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.OIL, color.CRITICAL } } }
})

addBreakdown("CONROD_BEARINGS", {
    system = systems.ENGINE, part = parts.CONROD_BEARINGS, isApplicable = getHasEngine,
        causes = { primary = { "flf", "hmf" }, secondary = { "sf", "mlf" } }, component = "SLEEVE_BEARING", branches = 2,
        progress = 1.4
}, {
    { },
    { },
    { { "ENGINE_KNOCKING_NOISE_EFFECT", 0.8 }, { "ENGINE_HEAT_MODIFIER", 0.35 }, lamps = { { db.OIL, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.OIL, color.CRITICAL } } }
})

addBreakdown("ELECTRIC_MOTOR_BEARING_WEAR", {
    system = systems.ENGINE, part = parts.ELECTRIC_MOTOR_BEARINGS, isApplicable = getIsElectricVehicle,
        causes = { primary = {}, secondary = { "hmf" } }, component = "BALL_BEARING", progress = 1.2
}, {
    { { "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", 1.0 }, { "FUEL_CONSUMPTION_MODIFIER", 0.03 } },
    { { "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", 1.5 }, { "FUEL_CONSUMPTION_MODIFIER", 0.06 },
        { "ENGINE_TORQUE_MODIFIER", -0.05 }, lamps = { { db.ENGINE, color.WARNING } } },
    { { "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", 2.0 }, { "FUEL_CONSUMPTION_MODIFIER", 0.1 },
        { "ENGINE_TORQUE_MODIFIER", -0.12 }, { "ENGINE_HEAT_MODIFIER", 0.1 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine(), lamps = { { db.ENGINE, color.CRITICAL }, { db.WARNING, color.CRITICAL } } }
})

addBreakdown("ELECTRIC_MOTOR_WINDING_FAULT", {
    system = systems.ENGINE, part = parts.ELECTRIC_MOTOR_WINDINGS, isApplicable = getIsElectricVehicle,
        causes = { primary = { "hmf" }, secondary = { "mlf" } }, component = "AC_MOTOR", progress = 1.3
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.08 }, { "ENGINE_HEAT_MODIFIER", 0.05 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.18 }, { "FUEL_CONSUMPTION_MODIFIER", 0.08 }, { "ENGINE_HEAT_MODIFIER", 0.1 },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "FUEL_CONSUMPTION_MODIFIER", 0.15 }, { "ENGINE_STALLS_CHANCE", 15.0 },
        { "ENGINE_HEAT_MODIFIER", 0.2 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine(), lamps = { { db.ENGINE, color.CRITICAL }, { db.WARNING, color.CRITICAL } } }
})

addBreakdown("MOTOR_POSITION_SENSOR_FAULT", {
    system = systems.ENGINE, part = parts.MOTOR_POSITION_SENSOR, isApplicable = getIsElectricVehicle,
        causes = { primary = { "hmf" }, secondary = {} }, component = "TRANSDUCER"
}, {
    { { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.4, cruiseState = 0, duration = 300, motorLoad = 0.2, status = "IDLE", timer = 0 } } },
    { { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 0.6, cruiseState = 0, duration = 400, motorLoad = 0.2, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.1 }, lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_HESITATION_CHANCE", 0.1, { amplitude = 0.8, cruiseState = 0, duration = 500, motorLoad = 0.2, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.2 }, { "ENGINE_STALLS_CHANCE", 10.0 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine(), lamps = { { db.ENGINE, color.CRITICAL }, { db.WARNING, color.CRITICAL } } }
})

addBreakdown("MANUAL_TRANSMISSION_CLUTCH_WEAR", {
    system = systems.TRANSMISSION, part = parts.CLUTCH, isApplicable = getHasClutchPedal, isCanProgress = getIsRolling,
        causes = { primary = { "lf" }, secondary = { "pof", "sf" } }, component = "FRICTION_CLUTCH", branches = 2,
        texts = "transmission_slip"
}, {
    { { "TRANSMISSION_SLIP_EFFECT", 0.2, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 0.1, { duration = 1500, status = "IDLE", timer = 0 }, branch = 2 },
        description = "rms_breakdowns_transmission_slip_stage1_description",
        branchDescriptions = { "rms_breakdowns_transmission_slip_stage1_description", "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage1_description" } },
    { { "TRANSMISSION_SLIP_EFFECT", 0.4, branch = 1 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 0.2, { duration = 1800, status = "IDLE", timer = 0 }, branch = 2 },
        description = "rms_breakdowns_transmission_slip_stage2_description", lamps = { { db.TRANSMISSION, color.WARNING } },
        branchDescriptions = { "rms_breakdowns_transmission_slip_stage2_description", "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage2_description" } },
    { { "TRANSMISSION_SLIP_EFFECT", 0.6, branch = 1 }, { "FUEL_CONSUMPTION_MODIFIER", 0.5, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 0.5, { duration = 2200, status = "IDLE", timer = 0 }, branch = 2 },
        description = "rms_breakdowns_transmission_slip_stage3_description",
        lamps = { { db.TRANSMISSION, color.CRITICAL } },
        branchDescriptions = { "rms_breakdowns_transmission_slip_stage3_description", "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage3_description" } },
    { { "TRANSMISSION_SLIP_EFFECT", 1.0, { disableAi = true }, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 1.0, { disableAi = true, duration = 2200, status = "IDLE", timer = 0 }, branch = 2 },
        description = "rms_breakdowns_transmission_slip_stage4_description",
        lamps = { { db.TRANSMISSION, color.CRITICAL } },
        branchDescriptions = { "rms_breakdowns_transmission_slip_stage4_description", "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage4_description" } }
})

addBreakdown("MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION", {
    system = systems.TRANSMISSION, part = parts.SYNCHRONIZER, isApplicable = getHasSynchronizers,
        isCanProgress = getIsRolling, causes = { primary = { "lf", "pof" }, secondary = { "sf" } },
        component = "FRICTION_CLUTCH", texts = "transmission_synchronizer_malfunction", progress = 1.3
}, {
    { { "GEAR_SHIFT_FAILURE_CHANCE", 0.1, { duration = 1500, status = "IDLE", timer = 0 } },
        { "GEAR_REJECTION_CHANCE", 20.0, { duration = 2000, status = "IDLE", timer = 0 } } },
    { { "GEAR_SHIFT_FAILURE_CHANCE", 0.2, { duration = 1800, status = "IDLE", timer = 0 } },
        { "GEAR_REJECTION_CHANCE", 10.0, { duration = 2000, status = "IDLE", timer = 0 } },
        lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "GEAR_SHIFT_FAILURE_CHANCE", 0.5, { duration = 2200, status = "IDLE", timer = 0 } },
        { "GEAR_REJECTION_CHANCE", 3.0, { duration = 2000, status = "IDLE", timer = 0 } },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "GEAR_SHIFT_FAILURE_CHANCE", 1.0, { disableAi = true, duration = 2200, status = "IDLE", timer = 0 } },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("GEARBOX_BEARING_FAILURE", {
    system = systems.TRANSMISSION, part = parts.GEARBOX_BEARINGS, isApplicable = getHasGearbox,
        isCanProgress = getIsRolling, causes = { primary = { "flf", "pof" }, secondary = { "sf", "hfbf" } },
        component = "ROLLER_BEARING", progress = 1.3
}, {
    { { "GEARBOX_BEARING_NOISE_EFFECT", 0.3 } },
    { { "GEARBOX_BEARING_NOISE_EFFECT", 0.8 } },
    { { "GEARBOX_BEARING_NOISE_EFFECT", 1.0 } },
    { { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } } }
})

addBreakdown("POWERSHIFT_CLUTCH_FAILURE", {
    system = systems.TRANSMISSION, part = parts.POWERSHIFT_CLUTCHES, isApplicable = isPowershiftClutchBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET", branches = 2, progress = 1.1
}, {
    { { "TRANSMISSION_SLIP_EFFECT", 0.2, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.2, { backup = 0, duration = 700, status = "IDLE", timer = 0 }, branch = 2 } },
    { { "TRANSMISSION_SLIP_EFFECT", 0.4, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.5, { backup = 0, duration = 1000, status = "IDLE", timer = 0 }, branch = 2 },
        lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "TRANSMISSION_SLIP_EFFECT", 0.6, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.99, { backup = 0, duration = 1500, status = "IDLE", timer = 0 }, branch = 2 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "TRANSMISSION_SLIP_EFFECT", 1.0, { disableAi = true }, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 1.0, { disableAi = true, duration = 0, status = "IDLE", timer = 0 }, branch = 2 },
        { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } }, lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("POWERSHIFT_REVERSER_FAILURE", {
    system = systems.TRANSMISSION, part = parts.POWERSHIFT_REVERSER, isApplicable = isPowershiftClutchBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET", branches = 2, progress = 1.1
}, {
    { { "TRANSMISSION_SLIP_EFFECT", 0.2, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.2, { backup = 0, duration = 700, status = "IDLE", timer = 0 }, branch = 2 } },
    { { "TRANSMISSION_SLIP_EFFECT", 0.4, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.5, { backup = 0, duration = 1000, status = "IDLE", timer = 0 }, branch = 2 },
        lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "TRANSMISSION_SLIP_EFFECT", 0.6, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.99, { backup = 0, duration = 1500, status = "IDLE", timer = 0 }, branch = 2 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "TRANSMISSION_SLIP_EFFECT", 1.0, { disableAi = true }, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 1.0, { disableAi = true, duration = 0, status = "IDLE", timer = 0 }, branch = 2 },
        { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } }, lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("TRANSMISSION_CONTROL_FAILURE", {
    system = systems.TRANSMISSION, part = parts.TRANSMISSION_CONTROL, isApplicable = isPowershiftBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET", branches = 2, progress = 1.1
}, {
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.2, { backup = 0, duration = 700, status = "IDLE", timer = 0 }, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 0.1, { duration = 1500, status = "IDLE", timer = 0 }, branch = 2 } },
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.5, { backup = 0, duration = 1000, status = "IDLE", timer = 0 }, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 0.2, { duration = 1800, status = "IDLE", timer = 0 }, branch = 2 },
        lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.99, { backup = 0, duration = 1500, status = "IDLE", timer = 0 }, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 0.5, { duration = 2200, status = "IDLE", timer = 0 }, branch = 2 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 1.0, { disableAi = true, duration = 0, status = "IDLE", timer = 0 }, branch = 1 },
        { "GEAR_SHIFT_FAILURE_CHANCE", 1.0, { disableAi = true, duration = 2200, status = "IDLE", timer = 0 }, branch = 2 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("TRANSMISSION_SENSOR_FAILURE", {
    system = systems.TRANSMISSION, part = parts.TRANSMISSION_SENSORS, isApplicable = getHasShiftSensors,
        isCanProgress = getIsRolling, causes = { primary = { "hotf" }, secondary = { "ctf" } }, component = "TRANSDUCER",
        branches = 2
}, {
    { { "GEAR_SHIFT_FAILURE_CHANCE", 0.2, { duration = 1800, status = "IDLE", timer = 0 }, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.5, { backup = 0, duration = 1000, status = "IDLE", timer = 0 }, branch = 2 },
        severity = MODERATE, lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "GEAR_SHIFT_FAILURE_CHANCE", 0.5, { duration = 2200, status = "IDLE", timer = 0 }, branch = 1 },
        { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.99, { backup = 0, duration = 1500, status = "IDLE", timer = 0 }, branch = 2 },
        severity = CRITICAL, lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("CVT_SENSOR_FAILURE", {
    system = systems.TRANSMISSION, part = parts.TRANSMISSION_SENSORS, isApplicable = isVariatorSensorApplicable,
        isCanProgress = getIsRolling, causes = { primary = { "hotf" }, secondary = { "ctf" } }, component = "TRANSDUCER",
        branches = 2
}, {
    { { "CVT_MAX_RATIO_MODIFIER", 0.4 }, severity = MODERATE, lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "CVT_MAX_RATIO_MODIFIER", 0.8 }, severity = CRITICAL, lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("TRANSMISSION_PUMP_MALFUNCTION", {
    system = systems.TRANSMISSION, part = parts.TRANSMISSION_PUMP, isApplicable = getHasTransmissionPump,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET", progress = 1.1
}, {
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.2, { backup = 0, duration = 700, status = "IDLE", timer = 0 } },
        { "CVT_PRESSURE_DROP_CHANCE", 2.0, { duration = 200, status = "IDLE", timer = 0 } },
        { "TRANSMISSION_PUMP_NOISE_EFFECT", 0.3 } },
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.5, { backup = 0, duration = 1000, status = "IDLE", timer = 0 } },
        { "CVT_PRESSURE_DROP_CHANCE", 1.0, { duration = 250, status = "IDLE", timer = 0 } },
        { "TRANSMISSION_PUMP_NOISE_EFFECT", 0.5 }, lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 0.99, { backup = 0, duration = 1500, status = "IDLE", timer = 0 } },
        { "CVT_PRESSURE_DROP_CHANCE", 0.5, { duration = 300, status = "IDLE", timer = 0 } },
        { "TRANSMISSION_PUMP_NOISE_EFFECT", 0.8 }, lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", 1.0, { disableAi = true, duration = 0, status = "IDLE", timer = 0 } },
        { "CVT_PRESSURE_DROP_CHANCE", 0.1, { duration = 300, status = "IDLE", timer = 0 } },
        { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } }, { "TRANSMISSION_PUMP_NOISE_EFFECT", 1.0 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("HYDROSTATIC_UNIT_MALFUNCTION", {
    system = systems.TRANSMISSION, part = parts.HYDROSTATIC_UNIT, isApplicable = isVariatorBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = { "lf" }, secondary = { "hotf", "pof" } },
        component = "CVT_REPLACEMENT_BUDGET", progress = 1.2
}, {
    { { "CVT_SLIP_EFFECT", 0.1 }, { "TRANSMISSION_HEAT_MODIFIER", 0.05 }, { "CVT_MAX_RATIO_MODIFIER", 0.3 },
        { "HYDROSTATIC_WHINE_NOISE_EFFECT", 0.3 } },
    { { "CVT_SLIP_EFFECT", 0.2 }, { "FUEL_CONSUMPTION_MODIFIER", 0.2 }, { "TRANSMISSION_HEAT_MODIFIER", 0.1 },
        { "CVT_MAX_RATIO_MODIFIER", 0.4 }, { "HYDROSTATIC_WHINE_NOISE_EFFECT", 0.5 },
        lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "CVT_SLIP_EFFECT", 0.5 }, { "FUEL_CONSUMPTION_MODIFIER", 0.25 }, { "TRANSMISSION_HEAT_MODIFIER", 0.15 },
        { "CVT_MAX_RATIO_MODIFIER", 0.5 }, { "HYDROSTATIC_WHINE_NOISE_EFFECT", 0.8 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "CVT_SLIP_EFFECT", 1.0, { disableAi = true } }, { "CVT_MAX_RATIO_MODIFIER", 0.8 },
        { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } }, { "HYDROSTATIC_WHINE_NOISE_EFFECT", 1.0 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION", {
    system = systems.TRANSMISSION, part = parts.CVT_HYDRAULIC_CONTROL_VALVE, isApplicable = isVariatorBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = { "hotf" }, secondary = { "ctf", "sf", "hfbf" } },
        component = "CVT_REPLACEMENT_BUDGET", texts = "hydraulic_control_valve_malfunction", progress = 1.1
}, {
    { { "CVT_PRESSURE_DROP_CHANCE", 2.0, { duration = 200, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "CVT_MAX_RATIO_MODIFIER", 0.3 } },
    { { "CVT_PRESSURE_DROP_CHANCE", 1.0, { duration = 250, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "TRANSMISSION_HEAT_MODIFIER", 0.05 }, { "CVT_MAX_RATIO_MODIFIER", 0.4 },
        lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "CVT_PRESSURE_DROP_CHANCE", 0.5, { duration = 300, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.2 }, { "TRANSMISSION_HEAT_MODIFIER", 0.1 }, { "CVT_MAX_RATIO_MODIFIER", 0.5 },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "CVT_MAX_RATIO_MODIFIER", 0.8 }, { "TRANSMISSION_HEAT_MODIFIER", 0.15 }, { "ENGINE_TORQUE_MODIFIER", -0.3 },
        { "CVT_PRESSURE_DROP_CHANCE", 0.1, { duration = 300, status = "IDLE", timer = 0 } },
        { "ENGINE_LIMP_EFFECT", -0.2, { disableAi = true, reason = "BREAKDOWN" } },
        lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("TRANSMISSION_OIL_LEAK", {
    system = systems.TRANSMISSION, part = parts.TRANSMISSION_SEAL, isApplicable = always, isCanProgress = getIsMotorStarted,
        causes = { primary = { "hotf", "ctf" }, secondary = {} }, component = "O_RING", progress = 0.8
}, {
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.02 }, hint = true },
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.08 }, lamps = { { db.WARNING, color.WARNING } }, hint = true },
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.25 }, lamps = { { db.TRANSMISSION, color.CRITICAL } }, hint = true },
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.8 }, lamps = { { db.TRANSMISSION, color.CRITICAL } }, hint = true }
})

addBreakdown("TRANSMISSION_OIL_COOLER_MALFUNCTION", {
    system = systems.TRANSMISSION, part = parts.TRANSMISSION_OIL_COOLER, isApplicable = isVariatorBreakdownApplicable,
        isCanProgress = getIsMotorStarted, causes = { primary = {}, secondary = {} }, component = "CONTROL_VALVE",
        progress = 1.3
}, {
    { { "TRANSMISSION_HEAT_MODIFIER", 0.05 } },
    { { "TRANSMISSION_HEAT_MODIFIER", 0.1 }, lamps = { { db.WARNING, color.WARNING } } },
    { { "TRANSMISSION_HEAT_MODIFIER", 0.15 }, lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "TRANSMISSION_HEAT_MODIFIER", 0.2 }, lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("TRANSMISSION_FILTER_CLOGGING", {
    system = systems.TRANSMISSION, part = parts.TRANSMISSION_FILTER, isApplicable = isTransmissionFilterApplicable
}, {
    { progressMultiplier = 0, lamps = { { db.TRANSMISSION, color.WARNING } } },
    { progressMultiplier = 0, lamps = { { db.TRANSMISSION, color.WARNING } } },
    { progressMultiplier = 0, lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("REAR_BEVEL_GEAR_FAILURE", {
    system = systems.TRANSMISSION, part = parts.REAR_BEVEL_GEAR, isApplicable = isWheelDifferentialBreakdownApplicable,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } }, component = "GEAR", progress = 1.2
}, {
    { { "GEAR_WHINE_NOISE_EFFECT", 0.3 } },
    { { "GEAR_WHINE_NOISE_EFFECT", 0.8 } },
    { { "GEAR_WHINE_NOISE_EFFECT", 1.0 } },
    { { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } } }
})

addBreakdown("FINAL_DRIVE_FAILURE", {
    system = systems.TRANSMISSION, part = parts.FINAL_DRIVES, isApplicable = isWheelDifferentialBreakdownApplicable,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } }, component = "GEAR", progress = 1.2
}, {
    { { "GEAR_WHINE_NOISE_EFFECT", 0.3 } },
    { { "GEAR_WHINE_NOISE_EFFECT", 0.8 } },
    { { "GEAR_WHINE_NOISE_EFFECT", 1.0 } },
    { { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } } }
})

addBreakdown("DIFFERENTIAL_FAILURE", {
    system = systems.TRANSMISSION, part = parts.DIFFERENTIAL, isApplicable = isWheelDifferentialBreakdownApplicable,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } }, component = "GEAR", progress = 1.2
}, {
    { { "GEAR_WHINE_NOISE_EFFECT", 0.3 } },
    { { "GEAR_WHINE_NOISE_EFFECT", 0.8 } },
    { { "GEAR_WHINE_NOISE_EFFECT", 1.0 } },
    { { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } } }
})

addBreakdown("FRONT_AXLE_SHAFT_WEAR", {
    system = systems.TRANSMISSION, part = parts.FRONT_AXLE_SHAFT, isApplicable = getHasFrontDrive,
        isCanProgress = getIsRolling, causes = { primary = { "pof", "dwf" }, secondary = { "wsf", "sf" } },
        component = "COUPLING", progress = 1.2
}, {
    { { "FRONT_AXLE_SHAFT_NOISE_EFFECT", 0.3 }, hint = true },
    { { "FRONT_AXLE_SHAFT_NOISE_EFFECT", 0.5 }, hint = true },
    { { "FRONT_AXLE_SHAFT_NOISE_EFFECT", 0.8 }, hint = true },
    { { "FOUR_WD_ENGAGE_FAILURE", 1 }, hint = true }
})

addBreakdown("AXLE_BEARING_WEAR", {
    system = systems.TRANSMISSION, part = parts.AXLE_BEARINGS, isApplicable = isWheelDifferentialBreakdownApplicable,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } }, component = "ROLLER_BEARING",
        progress = 1.2
}, {
    { { "GEAR_WHINE_NOISE_EFFECT", 0.3 }, hint = true },
    { { "GEAR_WHINE_NOISE_EFFECT", 0.5 }, hint = true },
    { { "GEAR_WHINE_NOISE_EFFECT", 0.8 }, hint = true },
    { { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } }, hint = true }
})

addBreakdown("DIFF_LOCK_CONTROL_FAILURE", {
    system = systems.TRANSMISSION, part = parts.DIFF_LOCK_CONTROL, isApplicable = getHasDrivetrain,
        causes = { primary = { "hotf" }, secondary = { "ctf", "sf", "hfbf" } }, component = "SOLENOID_VALVE", branches = 2
}, {
    { { "DIFF_LOCK_ENGAGE_FAILURE", 1, branch = 1 }, { "DIFF_LOCK_STUCK_ENGAGED", 1, branch = 2 }, severity = MAJOR,
        lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("FOUR_WD_CONTROL_FAILURE", {
    system = systems.TRANSMISSION, part = parts.FOUR_WD_CONTROL, isApplicable = getHasFrontDrive,
        causes = { primary = { "hotf" }, secondary = { "ctf", "sf", "hfbf" } }, component = "SOLENOID_VALVE", branches = 2
}, {
    { { "FOUR_WD_ENGAGE_FAILURE", 1, branch = 1 }, { "FOUR_WD_STUCK_ENGAGED", 1, branch = 2 }, severity = MAJOR,
        lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("REDUCER_GEAR_WEAR", {
    system = systems.TRANSMISSION, part = parts.REDUCER, isApplicable = isReducerBreakdownApplicable,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } }, component = "GEAR", progress = 1.2
}, {
    { { "GEAR_WHINE_NOISE_EFFECT", 1.0 } },
    { { "GEAR_WHINE_NOISE_EFFECT", 1.5 }, { "FUEL_CONSUMPTION_MODIFIER", 0.05 }, { "TRANSMISSION_HEAT_MODIFIER", 0.05 },
        lamps = { { db.TRANSMISSION, color.WARNING } } },
    { { "GEAR_WHINE_NOISE_EFFECT", 2.0 }, { "FUEL_CONSUMPTION_MODIFIER", 0.1 }, { "ENGINE_TORQUE_MODIFIER", -0.1 },
        { "TRANSMISSION_HEAT_MODIFIER", 0.15 }, lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "DRIVE_LOSS_EFFECT", 1, { disableAi = true } }, lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("CVT_ADDON_MALFUNCTION", {
    system = systems.TRANSMISSION, part = parts.CVT, isApplicable = hasCVTAddon, isCanProgress = never, progress = 1.4
}, {
    { },
    { lamps = { { db.TRANSMISSION, color.WARNING } } },
    { lamps = { { db.TRANSMISSION, color.CRITICAL } } },
    { { "CVT_SLIP_EFFECT", 1.0, { disableAi = true } }, lamps = { { db.TRANSMISSION, color.CRITICAL } } }
})

addBreakdown("HYDRAULIC_PUMP_MALFUNCTION", {
    system = systems.HYDRAULICS, part = parts.HYDRAULIC_PUMP, isApplicable = isHydraulicBreakdownApplicable,
        isCanProgress = getWearsWhileFlowing("HYDRAULIC_PUMP_MALFUNCTION"),
        causes = { primary = { "cof", "hof", "sf" }, secondary = { "flf", "hfbf" } }, component = "CENTRIFUGAL_PUMP",
        branches = 2, progress = 1.1
}, {
    { { "HYDRAULIC_SPEED_MODIFIER", -0.2, branch = 1 },
        { "HYDRAULIC_SPEED_MODIFIER", -1.0, { disableAi = true }, branch = 2 },
        { "HYDRAULIC_PUMP_NOISE_EFFECT", 0.3, branch = 1 },
        description = "rms_breakdowns_hydraulic_pump_malfunction_stage1_description",
        lamps = { { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_pump_malfunction_stage1_description", "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description" } },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.4, branch = 1 },
        { "HYDRAULIC_SPEED_MODIFIER", -1.0, { disableAi = true }, branch = 2 },
        { "HYDRAULIC_PUMP_NOISE_EFFECT", 0.5, branch = 1 },
        description = "rms_breakdowns_hydraulic_pump_malfunction_stage2_description",
        lamps = { { db.WARNING, color.WARNING, branch = 1 }, { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_pump_malfunction_stage2_description", "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description" } },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.75, branch = 1 },
        { "HYDRAULIC_SPEED_MODIFIER", -1.0, { disableAi = true }, branch = 2 },
        { "HYDRAULIC_PUMP_NOISE_EFFECT", 0.8, branch = 1 },
        description = "rms_breakdowns_hydraulic_pump_malfunction_stage3_description",
        lamps = { { db.WARNING, color.CRITICAL, branch = 1 }, { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_pump_malfunction_stage3_description", "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description" } },
    { { "HYDRAULIC_SPEED_MODIFIER", -1.0, { disableAi = true }, branch = 1 },
        { "HYDRAULIC_SPEED_MODIFIER", -1.0, { disableAi = true }, branch = 2 },
        { "HYDRAULIC_PUMP_NOISE_EFFECT", 1.0, branch = 1 },
        description = "rms_breakdowns_hydraulic_pump_malfunction_stage4_description",
        lamps = { { db.WARNING, color.CRITICAL, branch = 1 }, { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_pump_malfunction_stage4_description", "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description" } }
})

addBreakdown("HYDRAULIC_SPOOL_VALVE_MALFUNCTION", {
    system = systems.HYDRAULICS, part = parts.HYDRAULIC_SPOOL_VALVE, isApplicable = isHydraulicActuatorBreakdownApplicable,
        isCanProgress = getWearsWhileFlowing("HYDRAULIC_SPOOL_VALVE_MALFUNCTION"),
        causes = { primary = { "of", "sf" }, secondary = { "hfbf" } }, component = "CONTROL_VALVE", branches = 2,
        texts = "hydraulic_spool_valve", progress = 1.1
}, {
    { { "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", -0.1, { childVehicleHash = "" }, branch = 1 },
        { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 },
        description = "rms_breakdowns_hydraulic_spool_valve_stage1_description",
        branchDescriptions = { "rms_breakdowns_hydraulic_spool_valve_stage1_description", "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description" } },
    { { "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", -0.2, { childVehicleHash = "" }, branch = 1 },
        { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 },
        description = "rms_breakdowns_hydraulic_spool_valve_stage2_description", lamps = { { db.WARNING, color.WARNING } },
        branchDescriptions = { "rms_breakdowns_hydraulic_spool_valve_stage2_description", "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description" } },
    { { "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", -0.35, { childVehicleHash = "" }, branch = 1 },
        { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 },
        description = "rms_breakdowns_hydraulic_spool_valve_stage3_description", lamps = { { db.WARNING, color.CRITICAL } },
        branchDescriptions = { "rms_breakdowns_hydraulic_spool_valve_stage3_description", "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description" } },
    { { "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", -0.5, { childVehicleHash = "" }, branch = 1 },
        { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 },
        description = "rms_breakdowns_hydraulic_spool_valve_stage4_description", lamps = { { db.WARNING, color.CRITICAL } },
        branchDescriptions = { "rms_breakdowns_hydraulic_spool_valve_stage4_description", "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description" } }
})

addBreakdown("LIFT_VALVE_FAILURE", {
    system = systems.HYDRAULICS, part = parts.LIFT_VALVE, isApplicable = isHitchLiftBreakdownApplicable,
        getNameVariant = getLiftVariant, variantParts = { header = parts.HEADER_LIFT_VALVE },
        causes = { primary = { "of", "sf" }, secondary = { "hfbf" } }, component = "SOLENOID_VALVE", branches = 2
}, {
    { { "HYDRAULIC_HOLD_DRIFT_EFFECT", 0.05, { status = "IDLE", timer = 0 }, branch = 1 },
        { "LIFT_CONTROL_FAILURE", 1, branch = 2 }, severity = MAJOR, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("LIFT_POSITION_SENSOR_FAILURE", {
    system = systems.HYDRAULICS, part = parts.LIFT_POSITION_SENSOR, isApplicable = getHasLiftSensor,
        getNameVariant = getLiftVariant, variantParts = { header = parts.HEADER_HEIGHT_SENSOR },
        causes = { primary = {}, secondary = {} }, component = "TRANSDUCER"
}, {
    { { "HYDRAULIC_HOLD_DRIFT_EFFECT", 0.05, { status = "IDLE", timer = 0 } }, severity = MAJOR,
        lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("LOADER_CONTROL_FAILURE", {
    system = systems.HYDRAULICS, part = parts.LOADER_CONTROL, isApplicable = isFrontLoaderPivotBreakdownApplicable,
        isCanProgress = getIsMotorStarted, getNameVariant = getLoaderVariant,
        variantParts = { arm = parts.MILLING_ARM_CONTROL, blade = parts.BLADE_ARM_CONTROL, boom = parts.BOOM_CONTROL, mast = parts.MAST_CONTROL },
        causes = { primary = { "of" }, secondary = { "vf" } }, component = "ELECTRO_MECHANICAL", progress = 1.1
}, {
    { { "LOADER_CONTROL_EFFECT", -0.25 } },
    { { "LOADER_CONTROL_EFFECT", -0.5 }, lamps = { { db.WARNING, color.WARNING } } },
    { { "LOADER_CONTROL_EFFECT", -0.75 }, lamps = { { db.WARNING, color.CRITICAL } } },
    { { "LOADER_CONTROL_EFFECT", -1 }, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("HYDRAULIC_CYLINDER_INTERNAL_LEAK", {
    system = systems.HYDRAULICS, part = parts.HYDRAULIC_CYLINDER, isApplicable = isHydraulicLiftBreakdownApplicable,
        isCanProgress = getIsLiftWorking, causes = { primary = { "hlf", "of", "vf" }, secondary = { "hfbf" } },
        component = "O_RING", branches = 2, progress = 0.6
}, {
    { { "HYDRAULIC_HOLD_DRIFT_EFFECT", 0.01, { status = "IDLE", timer = 0 }, branch = 1 },
        { "HYDRAULIC_FLUID_LEAK_RATE", 0.02, branch = 2 },
        description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage1_description",
        branchDescriptions = { "rms_breakdowns_hydraulic_cylinder_internal_leak_stage1_description", "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage1_description" } },
    { { "HYDRAULIC_HOLD_DRIFT_EFFECT", 0.03, { status = "IDLE", timer = 0 }, branch = 1 },
        { "HYDRAULIC_FLUID_LEAK_RATE", 0.08, branch = 2 },
        description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage2_description",
        lamps = { { db.WARNING, color.WARNING, branch = 1 }, { db.WARNING, color.WARNING, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_cylinder_internal_leak_stage2_description", "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage2_description" } },
    { { "HYDRAULIC_HOLD_DRIFT_EFFECT", 0.05, { status = "IDLE", timer = 0 }, branch = 1 },
        { "HYDRAULIC_FLUID_LEAK_RATE", 0.25, branch = 2 },
        description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage3_description",
        lamps = { { db.WARNING, color.CRITICAL, branch = 1 }, { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_cylinder_internal_leak_stage3_description", "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage3_description" } },
    { { "HYDRAULIC_HOLD_DRIFT_EFFECT", 1.0, { status = "IDLE", timer = 0 }, branch = 1 },
        { "HYDRAULIC_FLUID_LEAK_RATE", 0.8, branch = 2 },
        description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage4_description",
        lamps = { { db.WARNING, color.CRITICAL, branch = 1 }, { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_cylinder_internal_leak_stage4_description", "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage4_description" } }
})

addBreakdown("HYDRAULIC_QUICK_COUPLER_FAILURE", {
    system = systems.HYDRAULICS, part = parts.HYDRAULIC_QUICK_COUPLERS,
        isApplicable = isHydraulicActuatorBreakdownApplicable,
        isCanProgress = getWearsWhileFlowing("HYDRAULIC_QUICK_COUPLER_FAILURE"),
        causes = { primary = { "hlf", "vf" }, secondary = {} }, component = "O_RING", branches = 2, progress = 0.8
}, {
    { { "HYDRAULIC_FLUID_LEAK_RATE", 0.02, branch = 1 }, { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 } },
    { { "HYDRAULIC_FLUID_LEAK_RATE", 0.08, branch = 1 }, { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 },
        lamps = { { db.WARNING, color.WARNING, branch = 1 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage2_description", "rms_breakdowns_hydraulic_quick_coupler_failure_branch2_stage1_description" } },
    { { "HYDRAULIC_FLUID_LEAK_RATE", 0.25, branch = 1 }, { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 },
        lamps = { { db.WARNING, color.CRITICAL, branch = 1 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage3_description", "rms_breakdowns_hydraulic_quick_coupler_failure_branch2_stage1_description" } },
    { { "HYDRAULIC_FLUID_LEAK_RATE", 0.8, branch = 1 }, { "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", 1, branch = 2 },
        lamps = { { db.WARNING, color.CRITICAL, branch = 1 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage4_description", "rms_breakdowns_hydraulic_quick_coupler_failure_branch2_stage1_description" } }
})

addBreakdown("HYDRAULIC_HOSE_EXTERNAL_LEAK", {
    system = systems.HYDRAULICS, part = parts.HYDRAULIC_HOSE, isApplicable = isHydraulicHoseBreakdownApplicable,
        isCanProgress = getIsHydraulicsWorking, causes = { primary = { "hlf", "vf" }, secondary = {} },
        component = "RUBBER_DIAPHRAGM", progress = 0.8
}, {
    { { "HYDRAULIC_SPEED_MODIFIER", -0.05 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.02 }, hint = true },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.08 },
        lamps = { { db.WARNING, color.WARNING } }, hint = true },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.2 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.25 },
        lamps = { { db.WARNING, color.CRITICAL } }, hint = true },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.35 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.8 }, { "HOSE_BURST_NOISE_EFFECT", 1.0 },
        lamps = { { db.WARNING, color.CRITICAL } }, hint = true }
})

addBreakdown("HYDRAULIC_FILTER_CLOGGING", {
    system = systems.HYDRAULICS, part = parts.HYDRAULIC_FILTER, isApplicable = isHydraulicBreakdownApplicable
}, {
    { { "HYDRAULIC_SPEED_MODIFIER", -0.1 }, progressMultiplier = 0 },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.25 }, progressMultiplier = 0, lamps = { { db.WARNING, color.WARNING } } },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.45 }, progressMultiplier = 0, lamps = { { db.WARNING, color.CRITICAL } } },
    { { "HYDRAULIC_SPEED_MODIFIER", -0.7 }, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("HYDRAULIC_OIL_COOLER_MALFUNCTION", {
    system = systems.HYDRAULICS, part = parts.HYDRAULIC_OIL_COOLER, isApplicable = isHydraulicBreakdownApplicable,
        isCanProgress = getIsHydraulicsWorking, causes = { primary = { "hof", "sf", "of" }, secondary = { "vf" } },
        component = "HEAT_EXCHANGER", branches = 2, progress = 0.9
}, {
    { { "HYDRAULIC_HEAT_MODIFIER", 0.05, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.02, branch = 2 },
        description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage1_description",
        branchDescriptions = { "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage1_description", "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage1_description" } },
    { { "HYDRAULIC_HEAT_MODIFIER", 0.1, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.08, branch = 2 },
        description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage2_description",
        lamps = { { db.WARNING, color.WARNING, branch = 1 }, { db.WARNING, color.WARNING, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage2_description", "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage2_description" } },
    { { "HYDRAULIC_HEAT_MODIFIER", 0.15, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.25, branch = 2 },
        description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage3_description",
        lamps = { { db.WARNING, color.WARNING, branch = 1 }, { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage3_description", "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage3_description" } },
    { { "HYDRAULIC_HEAT_MODIFIER", 0.2, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.8, branch = 2 },
        description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage4_description",
        lamps = { { db.WARNING, color.CRITICAL, branch = 1 }, { db.WARNING, color.CRITICAL, branch = 2 } },
        branchDescriptions = { "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage4_description", "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage4_description" } }
})

addBreakdown("PTO_CLUTCH_WEAR", {
    system = systems.PTO, part = parts.PTO_CLUTCH, isApplicable = isPtoBreakdownApplicable, isCanProgress = getIsPtoTurning,
        causes = { primary = { "plf", "pef" }, secondary = { "sf" } }, component = "FRICTION_CLUTCH", branches = 2,
        hints = { [2] = "pto_clutch_wear_branch2" }
}, {
    { { "PTO_AUTO_DISENGAGE_CHANCE", 40, { status = "IDLE" }, branch = 1 },
        description = "rms_breakdowns_pto_clutch_wear_stage1_description", hint = true,
        branchDescriptions = { "rms_breakdowns_pto_clutch_wear_stage1_description", "rms_breakdowns_pto_clutch_wear_branch2_stage1_description" } },
    { { "PTO_AUTO_DISENGAGE_CHANCE", 20, { status = "IDLE" }, branch = 1 },
        description = "rms_breakdowns_pto_clutch_wear_stage2_description",
        lamps = { { db.WARNING, color.WARNING, branch = 1 } }, hint = true,
        branchDescriptions = { "rms_breakdowns_pto_clutch_wear_stage2_description", "rms_breakdowns_pto_clutch_wear_branch2_stage2_description" } },
    { { "PTO_AUTO_DISENGAGE_CHANCE", 10, { status = "IDLE" }, branch = 1 }, { "PTO_STUCK_ENGAGED_CHANCE", 0.5, branch = 2 },
        description = "rms_breakdowns_pto_clutch_wear_stage3_description", lamps = { { db.WARNING, color.CRITICAL } },
        branchDescriptions = { "rms_breakdowns_pto_clutch_wear_stage3_description", "rms_breakdowns_pto_clutch_wear_branch2_stage3_description" } },
    { { "PTO_FAILURE", 1.0, { disableAi = true }, branch = 1 },
        { "PTO_STUCK_ENGAGED_CHANCE", 1.0, { disableAi = true }, branch = 2 },
        description = "rms_breakdowns_pto_clutch_wear_stage4_description", lamps = { { db.WARNING, color.CRITICAL } },
        branchDescriptions = { "rms_breakdowns_pto_clutch_wear_stage4_description", "rms_breakdowns_pto_clutch_wear_branch2_stage4_description" } }
})

addBreakdown("PTO_OUTPUT_BEARING_WEAR", {
    system = systems.PTO, part = parts.PTO_OUTPUT_BEARING, isApplicable = isPtoBreakdownApplicable,
        isCanProgress = getIsPtoTurning, causes = { primary = { "plf", "sf" }, secondary = { "pef" } },
        component = "PTO_OUTPUT_SHARED_BUDGET", progress = 1.2
}, {
    { { "PTO_BEARING_NOISE_EFFECT", 0.7 } },
    { { "PTO_BEARING_NOISE_EFFECT", 1.2 }, lamps = { { db.WARNING, color.WARNING } } },
    { { "PTO_BEARING_NOISE_EFFECT", 1.7 }, lamps = { { db.WARNING, color.CRITICAL } } },
    { { "PTO_BEARING_NOISE_EFFECT", 1.7 }, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("PTO_OUTPUT_SEAL_LEAK", {
    system = systems.PTO, part = parts.PTO_OUTPUT_SEAL, isApplicable = isPtoBreakdownApplicable,
        isCanProgress = getIsMotorStarted, causes = { primary = { "plf" }, secondary = { "sf" } },
        component = "MECHANICAL_SEAL", progress = 0.8
}, {
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.01 }, hint = true },
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.04 }, lamps = { { db.WARNING, color.WARNING } }, hint = true },
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.12 }, lamps = { { db.TRANSMISSION, color.CRITICAL } }, hint = true },
    { { "TRANSMISSION_OIL_LEAK_RATE", 0.4 }, lamps = { { db.TRANSMISSION, color.CRITICAL } }, hint = true }
})

addBreakdown("PTO_ENGAGEMENT_SOLENOID_FAILURE", {
    system = systems.PTO, part = parts.PTO_ENGAGEMENT_SOLENOID, isApplicable = getHasElectricPtoEngagement,
        isCanProgress = getIsMotorStarted, causes = { primary = { "sf" }, secondary = {} },
        component = "PTO_CONTROL_SHARED_BUDGET", branches = 2, progress = 1.1
}, {
    { { "PTO_AUTO_DISENGAGE_CHANCE", 40, { status = "IDLE" }, branch = 1 },
        { "PTO_ENGAGEMENT_BLOCKED_CHANCE", 0.1, branch = 2 } },
    { { "PTO_AUTO_DISENGAGE_CHANCE", 20, { status = "IDLE" }, branch = 1 },
        { "PTO_ENGAGEMENT_BLOCKED_CHANCE", 0.3, branch = 2 }, lamps = { { db.WARNING, color.WARNING } } },
    { { "PTO_AUTO_DISENGAGE_CHANCE", 10, { status = "IDLE" }, branch = 1 },
        { "PTO_ENGAGEMENT_BLOCKED_CHANCE", 0.6, branch = 2 }, lamps = { { db.WARNING, color.CRITICAL } } },
    { { "PTO_FAILURE", 1.0, { disableAi = true }, branch = 1 }, { "PTO_FAILURE", 1.0, { disableAi = true }, branch = 2 },
        lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("PTO_ENGAGEMENT_SWITCH_FAILURE", {
    system = systems.PTO, part = parts.PTO_ENGAGEMENT_SWITCH, isApplicable = getHasElectricPtoEngagement,
        isCanProgress = getIsMotorStarted, causes = { primary = { "sf" }, secondary = {} },
        component = "PTO_CONTROL_SHARED_BUDGET", branches = 2, progress = 1.1
}, {
    { { "PTO_AUTO_DISENGAGE_CHANCE", 40, { status = "IDLE" }, branch = 1 },
        { "PTO_ENGAGEMENT_BLOCKED_CHANCE", 0.1, branch = 2 } },
    { { "PTO_AUTO_DISENGAGE_CHANCE", 20, { status = "IDLE" }, branch = 1 },
        { "PTO_ENGAGEMENT_BLOCKED_CHANCE", 0.3, branch = 2 }, lamps = { { db.WARNING, color.WARNING } } },
    { { "PTO_AUTO_DISENGAGE_CHANCE", 10, { status = "IDLE" }, branch = 1 },
        { "PTO_ENGAGEMENT_BLOCKED_CHANCE", 0.6, branch = 2 }, lamps = { { db.WARNING, color.CRITICAL } } },
    { { "PTO_FAILURE", 1.0, { disableAi = true }, branch = 1 }, { "PTO_FAILURE", 1.0, { disableAi = true }, branch = 2 },
        lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("PTO_OUTPUT_SHAFT_FAILURE", {
    system = systems.PTO, part = parts.PTO_OUTPUT_SHAFT, isApplicable = isPtoBreakdownApplicable,
        causes = { primary = { "plf", "sf" }, secondary = { "pef" } }, component = "PTO_OUTPUT_SHARED_BUDGET", branches = 2
}, {
    { { "PTO_FAILURE", 1.0, { disableAi = true }, branch = 1 }, { "PTO_FAILURE", 1.0, { disableAi = true }, branch = 2 },
        { "PTO_SPLINES_NOISE_EFFECT", 1.0, branch = 1 }, { "PTO_SHAFT_BREAK_NOISE_EFFECT", 1.0, branch = 2 },
        severity = CRITICAL, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("PTO_SPEED_SENSOR_FAILURE", {
    system = systems.PTO, part = parts.PTO_SPEED_SENSOR, isApplicable = getHasPtoSpeedSensor,
        causes = { primary = {}, secondary = {} }, component = "TRANSDUCER"
}, {
    { { "PTO_FAILURE", 1.0, { disableAi = true } }, severity = CRITICAL, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("PTO_BRAKE_FAILURE", {
    system = systems.PTO, part = parts.PTO_BRAKE, isApplicable = isPtoBreakdownApplicable,
        causes = { primary = {}, secondary = {} }, component = "PTO_BRAKE_SERVICE_PROXY"
}, {
    { { "PTO_FAILURE", 1.0, { disableAi = true } }, severity = CRITICAL, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("FRONT_PTO_CLUTCH_FAILURE", {
    system = systems.PTO, part = parts.FRONT_PTO_CLUTCH, isApplicable = getHasFrontPto,
        isCanProgress = getIsFrontPtoTurning, causes = { primary = { "pef" }, secondary = { "plf", "sf" } },
        component = "FRICTION_CLUTCH"
}, {
    { { "FRONT_PTO_AUTO_DISENGAGE_CHANCE", 40, { status = "IDLE" } } },
    { { "FRONT_PTO_AUTO_DISENGAGE_CHANCE", 20, { status = "IDLE" } }, lamps = { { db.WARNING, color.WARNING } } },
    { { "FRONT_PTO_AUTO_DISENGAGE_CHANCE", 10, { status = "IDLE" } }, lamps = { { db.WARNING, color.CRITICAL } } },
    { { "FRONT_PTO_FAILURE", 1.0, { disableAi = true } }, lamps = { { db.WARNING, color.CRITICAL } } }
})

addBreakdown("BRAKE_DISC_WEAR", {
    system = systems.CHASSIS, part = parts.BRAKE_DISCS, isApplicable = isServiceBrakeBreakdownApplicable,
        isCanProgress = always, causes = { primary = { "bmf" }, secondary = {} }, component = "BRAKE_SERVICE_BUDGET",
        progress = 0.9
}, {
    { { "BRAKE_FORCE_MODIFIER", -0.3 } },
    { { "BRAKE_FORCE_MODIFIER", -0.45 } },
    { { "BRAKE_FORCE_MODIFIER", -0.7 } },
    { { "BRAKE_FORCE_MODIFIER", -1.0, { disableAi = true } } }
})

addBreakdown("BRAKE_CONTROL_FAILURE", {
    system = systems.CHASSIS, part = parts.BRAKE_CONTROL, isApplicable = isServiceBrakeBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = { "bmf" }, secondary = {} }, component = "BRAKE_SERVICE_BUDGET",
        branches = 2, progress = 0.9, hints = { [1] = "brake_control_failure", [2] = "brake_control_failure_soft_pedal" }
}, {
    { { "BRAKE_PULL_EFFECT", 0.2, branch = 1 }, { "BRAKE_FORCE_MODIFIER", -0.3, branch = 2 }, hint = true },
    { { "BRAKE_PULL_EFFECT", 0.5, branch = 1 }, { "BRAKE_FORCE_MODIFIER", -0.45, branch = 2 },
        lamps = { { db.BRAKES, color.WARNING, branch = 2 } }, hint = true },
    { { "BRAKE_PULL_EFFECT", 1.2, branch = 1 }, { "BRAKE_FORCE_MODIFIER", -0.7, branch = 2 },
        lamps = { { db.BRAKES, color.CRITICAL, branch = 2 } }, hint = true },
    { { "BRAKE_PULL_EFFECT", 1.2, branch = 1 }, { "BRAKE_FORCE_MODIFIER", -1.0, { disableAi = true }, branch = 2 },
        lamps = { { db.BRAKES, color.CRITICAL, branch = 2 } }, hint = true }
})

addBreakdown("TRAILER_BRAKE_VALVE_FAILURE", {
    system = systems.CHASSIS, part = parts.TRAILER_BRAKE_VALVE, isApplicable = isTrailerBrakeValveApplicable,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = {} }, component = "TRAILER_BRAKE_VALVE",
        progress = 0.9
}, {
    { { "TRAILER_BRAKE_FAILURE", -0.3 }, hint = true },
    { { "TRAILER_BRAKE_FAILURE", -0.45 }, hint = true },
    { { "TRAILER_BRAKE_FAILURE", -0.7 }, hint = true },
    { { "TRAILER_BRAKE_FAILURE", -1.0 }, hint = true }
})

addBreakdown("PARK_BRAKE_MALFUNCTION", {
    system = systems.CHASSIS, part = parts.PARK_BRAKE, isApplicable = getHasParkBrake,
        causes = { primary = { "pbf" }, secondary = {} }, component = "FRICTION_CLUTCH", progress = 0.9
}, {
    { { "PARK_BRAKE_DRAG_EFFECT", 0.1 }, { "PARK_BRAKE_DRAG_NOISE_EFFECT", 0.3 } },
    { { "PARK_BRAKE_DRAG_EFFECT", 0.25 }, { "PARK_BRAKE_DRAG_NOISE_EFFECT", 0.5 } },
    { { "PARK_BRAKE_DRAG_EFFECT", 0.5 }, { "PARK_BRAKE_DRAG_NOISE_EFFECT", 0.8 }, lamps = { { db.BRAKES, color.WARNING } } },
    { { "PARK_BRAKE_DRAG_EFFECT", 1.0, { disableAi = true } }, { "PARK_BRAKE_DRAG_NOISE_EFFECT", 1.0 },
        lamps = { { db.BRAKES, color.CRITICAL } } }
})

addBreakdown("WHEEL_HUB_BEARING_WEAR", {
    system = systems.CHASSIS, part = parts.WHEEL_BEARING, isApplicable = getHasRoadWheel, isCanProgress = getIsRolling,
        causes = { primary = { "vf", "tif" }, secondary = { "lubf" } }, component = "ROLLER_BEARING", progress = 1.2
}, {
    { { "WHEEL_HUB_BEARING_NOISE_EFFECT", 1.0 }, { "MAX_SPEED_MODIFIER", 0.05 }, { "ENGINE_TORQUE_MODIFIER", -0.03 } },
    { { "WHEEL_HUB_BEARING_NOISE_EFFECT", 1.5 }, { "MAX_SPEED_MODIFIER", 0.1 }, { "ENGINE_TORQUE_MODIFIER", -0.05 } },
    { { "WHEEL_HUB_BEARING_NOISE_EFFECT", 2.0 }, { "MAX_SPEED_MODIFIER", 0.2 }, { "ENGINE_TORQUE_MODIFIER", -0.07 },
        { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 0.3 } },
    { { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 2.5 }, { "WHEEL_SEIZURE_EFFECT", 1.0, { disableAi = true } },
        lamps = { { db.BRAKES, color.CRITICAL } } }
})

addBreakdown("STEERING_LINKAGE_WEAR", {
    system = systems.CHASSIS, part = parts.STEERING_LINKAGE, isApplicable = isSteeredAxleBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = { "slf", "tif" }, secondary = { "vf", "lubf" } },
        component = "STEERING_COMPONENT_BUDGET", progress = 1.2
}, {
    { { "STEERING_STATIC_BIAS_EFFECT", 0.2 }, { "STEERING_PLAY_EFFECT", 0.5 }, { "STEERING_LINKAGE_NOISE_EFFECT", 0.3 } },
    { { "STEERING_STATIC_BIAS_EFFECT", 0.5 }, { "STEERING_PLAY_EFFECT", 1.2 }, { "STEERING_LINKAGE_NOISE_EFFECT", 0.5 } },
    { { "STEERING_STATIC_BIAS_EFFECT", 1.2 }, { "STEERING_PLAY_EFFECT", 2.5 }, { "STEERING_LINKAGE_NOISE_EFFECT", 0.8 } },
    { { "STEERING_WHEEL_FREE_EFFECT", 1.0, { disableAi = true } }, { "STEERING_LINKAGE_NOISE_EFFECT", 1.0 } }
})

addBreakdown("STEERING_KNUCKLE_PIVOT_WEAR", {
    system = systems.CHASSIS, part = parts.STEERING_KNUCKLE_PIVOT, isApplicable = isSteeredAxleBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = { "slf", "tif" }, secondary = { "vf", "lubf" } },
        component = "STEERING_COMPONENT_BUDGET", progress = 1.2
}, {
    { { "STEERING_PLAY_EFFECT", 0.5 }, { "STEERING_KNUCKLE_NOISE_EFFECT", 0.3 }, hint = true },
    { { "STEERING_PLAY_EFFECT", 1.2 }, { "STEERING_KNUCKLE_NOISE_EFFECT", 0.5 }, hint = true },
    { { "STEERING_PLAY_EFFECT", 2.5 }, { "STEERING_KNUCKLE_NOISE_EFFECT", 0.8 }, hint = true },
    { { "STEERING_PLAY_EFFECT", 2.5 }, { "STEERING_KNUCKLE_NOISE_EFFECT", 1.0 }, hint = true }
})

addBreakdown("STEERING_ORBITROL_MALFUNCTION", {
    system = systems.CHASSIS, part = parts.STEERING_ORBITROL, isApplicable = isSteeringUnitBreakdownApplicable,
        isCanProgress = getIsRolling, getNameVariant = getSteeringGearVariant,
        variantParts = { box = parts.STEERING_BOX, rack = parts.STEERING_RACK },
        causes = { primary = { "slf", "tif" }, secondary = { "vf", "lubf" } }, component = "STEERING_COMPONENT_BUDGET",
        progress = 1.2
}, {
    { { "STEERING_PLAY_EFFECT", 0.5 }, { "STEERING_ORBITROL_NOISE_EFFECT", 0.3 }, hint = true },
    { { "STEERING_PLAY_EFFECT", 1.2 }, { "STEERING_ORBITROL_NOISE_EFFECT", 0.5 }, hint = true },
    { { "STEERING_PLAY_EFFECT", 2.5 }, { "STEERING_ORBITROL_NOISE_EFFECT", 0.8 }, hint = true },
    { { "STEERING_PLAY_EFFECT", 2.5 }, { "STEERING_ORBITROL_NOISE_EFFECT", 1.0 }, hint = true }
})

addBreakdown("STEERING_CYLINDER_LEAK", {
    system = systems.CHASSIS, part = parts.STEERING_CYLINDER, isApplicable = getHasSteeringCylinder,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = {} }, component = "STEERING_COMPONENT_BUDGET",
        branches = 2, progress = 1.2, hints = { [1] = "steering_cylinder_leak", [2] = "steering_cylinder_leak_rod_seal" }
}, {
    { { "STEERING_STATIC_BIAS_EFFECT", 0.2, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.02, branch = 2 }, hint = true },
    { { "STEERING_STATIC_BIAS_EFFECT", 0.5, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.08, branch = 2 }, hint = true },
    { { "STEERING_STATIC_BIAS_EFFECT", 1.2, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.25, branch = 2 }, hint = true },
    { { "STEERING_STATIC_BIAS_EFFECT", 1.2, branch = 1 }, { "HYDRAULIC_FLUID_LEAK_RATE", 0.8, branch = 2 }, hint = true }
})

addBreakdown("LOADER_PIVOT_PIN_WEAR", {
    system = systems.CHASSIS, part = parts.LOADER_PINS_AND_BUSHINGS, isApplicable = isFrontLoaderPivotBreakdownApplicable,
        isCanProgress = getIsRolling, getNameVariant = getLoaderVariant,
        variantParts = { arm = parts.MILLING_ARM_PINS_AND_BUSHINGS, blade = parts.BLADE_ARM_PINS_AND_BUSHINGS, boom = parts.BOOM_PINS_AND_BUSHINGS, mast = parts.MAST_PINS_AND_BUSHINGS },
        causes = { primary = {}, secondary = {} }, component = "PIN", progress = 1.2, variantHints = true
}, {
    { { "LOADER_PINS_NOISE_EFFECT", 0.3 }, hint = true },
    { { "LOADER_PINS_NOISE_EFFECT", 0.5 }, hint = true },
    { { "LOADER_PINS_NOISE_EFFECT", 0.8 }, hint = true },
    { { "LOADER_PINS_NOISE_EFFECT", 1.0 }, hint = true }
})

addBreakdown("CAB_SUSPENSION_DAMPER_LEAK", {
    system = systems.CHASSIS, part = parts.CAB_SUSPENSION, isApplicable = isCabSuspensionApplicable,
        isCanProgress = getIsRolling, causes = { primary = { "vf" }, secondary = { "tif" } }, component = "MECHANICAL_SEAL",
        progress = 1.2
}, {
    { { "CAB_DAMPING_MODIFIER", -0.3 }, hint = true },
    { { "CAB_DAMPING_MODIFIER", -0.55 }, hint = true },
    { { "CAB_DAMPING_MODIFIER", -0.8 }, { "CAB_DAMPER_NOISE_EFFECT", 0.8 }, hint = true },
    { { "CAB_DAMPING_MODIFIER", -0.95 }, { "CAB_DAMPER_NOISE_EFFECT", 1.0 }, hint = true }
})

addBreakdown("TRACK_ROLLER_BEARING_WEAR", {
    system = systems.CHASSIS, part = parts.TRACK_ROLLERS, isApplicable = isCrawlerBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = {} }, component = "ROLLER_BEARING",
        progress = 1.2
}, {
    { { "TRACK_ROLLER_NOISE_EFFECT", 1.0 }, { "MAX_SPEED_MODIFIER", 0.05 }, { "ENGINE_TORQUE_MODIFIER", -0.03 }, hint = true },
    { { "TRACK_ROLLER_NOISE_EFFECT", 1.5 }, { "MAX_SPEED_MODIFIER", 0.1 }, { "ENGINE_TORQUE_MODIFIER", -0.05 }, hint = true },
    { { "TRACK_ROLLER_NOISE_EFFECT", 2.0 }, { "MAX_SPEED_MODIFIER", 0.2 }, { "ENGINE_TORQUE_MODIFIER", -0.07 },
        { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 0.3 }, hint = true },
    { { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 2.5 }, { "WHEEL_SEIZURE_EFFECT", 1.0, { disableAi = true } },
        lamps = { { db.BRAKES, color.CRITICAL } }, hint = true }
})

addBreakdown("TRACK_TENSIONER_MALFUNCTION", {
    system = systems.CHASSIS, part = parts.TRACK_TENSIONER, isApplicable = isCrawlerBreakdownApplicable,
        isCanProgress = getIsRolling, causes = { primary = {}, secondary = {} }, component = "O_RING", progress = 1.3
}, {
    { { "STEERING_STATIC_BIAS_EFFECT", 0.2 }, { "TRACK_CLATTER_NOISE_EFFECT", 1.0 },
        { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 0.5 }, { "MAX_SPEED_MODIFIER", 0.03 } },
    { { "STEERING_STATIC_BIAS_EFFECT", 0.5 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 400, motorLoad = 0.2, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "TRACK_CLATTER_NOISE_EFFECT", 1.5 },
        { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 1.0 }, { "MAX_SPEED_MODIFIER", 0.06 }, hint = true },
    { { "STEERING_STATIC_BIAS_EFFECT", 1.5 },
        { "ENGINE_HESITATION_CHANCE", 0.1, { amplitude = 0.6, cruiseState = 0, duration = 500, motorLoad = 0.2, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "TRACK_CLATTER_NOISE_EFFECT", 2.0 },
        { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 2.0 }, { "MAX_SPEED_MODIFIER", 0.15 },
        lamps = { { db.BRAKES, color.WARNING } }, hint = true },
    { { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", 2.5 }, { "WHEEL_SEIZURE_EFFECT", 1.0, { disableAi = true } },
        lamps = { { db.BRAKES, color.CRITICAL } }, hint = true }
})

addBreakdown("THERMOSTAT_MALFUNCTION", {
    system = systems.COOLING, part = parts.THERMOSTAT, isApplicable = getHasEngine,
        causes = { primary = {}, secondary = { "sf" } }, component = "CONTROL_VALVE", branches = 2, progress = 1.4
}, {
    { { "THERMOSTAT_STUCK_EFFECT", -1.0, { stuckPosition = 1.0 }, branch = 1 },
        { "THERMOSTAT_HEALTH_MODIFIER", -0.3, branch = 2 } },
    { { "THERMOSTAT_STUCK_EFFECT", -1.0, { stuckPosition = 1.0 }, branch = 1 },
        { "THERMOSTAT_HEALTH_MODIFIER", -0.6, branch = 2 }, lamps = { { db.WARNING, color.WARNING, branch = 2 } } },
    { { "THERMOSTAT_STUCK_EFFECT", -1.0, { stuckPosition = 1.0 }, branch = 1 },
        { "THERMOSTAT_HEALTH_MODIFIER", -0.8, branch = 2 }, lamps = { { db.COOLANT, color.WARNING, branch = 2 } } },
    { { "THERMOSTAT_STUCK_EFFECT", -1.0, { stuckPosition = 1.0 }, branch = 1 },
        { "THERMOSTAT_STUCK_EFFECT", -1.0, { stuckPosition = 0.0 }, branch = 2 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 2 } } }
})

addBreakdown("COOLANT_HOSE_FAILURE", {
    system = systems.COOLING, part = parts.COOLANT_HOSES, isApplicable = always,
        causes = { primary = { "ohf" }, secondary = {} }, component = "HYDRAULIC_GASKET", branches = 2, progress = 0.6,
        hints = { [1] = "coolant_leak", [2] = "thermal_water_pump" }
}, {
    { { "COOLANT_LEAK_RATE", 0.02, branch = 1 }, { "RADIATOR_HEALTH_MODIFIER", -0.2, branch = 2 },
        { "COOLANT_STEAM_NOISE_EFFECT", 0.3, branch = 1 }, hint = true },
    { { "COOLANT_LEAK_RATE", 0.08, branch = 1 }, { "RADIATOR_HEALTH_MODIFIER", -0.4, branch = 2 },
        { "COOLANT_STEAM_NOISE_EFFECT", 0.5, branch = 1 }, lamps = { { db.COOLANT, color.WARNING, branch = 2 } },
        hint = true },
    { { "COOLANT_LEAK_RATE", 0.25, branch = 1 }, { "RADIATOR_HEALTH_MODIFIER", -0.6, branch = 2 },
        { "COOLANT_STEAM_NOISE_EFFECT", 0.8, branch = 1 },
        lamps = { { db.COOLANT, color.WARNING, branch = 1 }, { db.COOLANT, color.CRITICAL, branch = 2 } }, hint = true },
    { { "COOLANT_LEAK_RATE", 0.8, branch = 1 }, { "RADIATOR_HEALTH_MODIFIER", -0.85, branch = 2 },
        { "COOLANT_STEAM_NOISE_EFFECT", 1.0, branch = 1 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.CRITICAL, branch = 2 } }, hint = true }
})

addBreakdown("EXPANSION_TANK_FAILURE", {
    system = systems.COOLING, part = parts.EXPANSION_TANK, isApplicable = always,
        causes = { primary = { "ohf" }, secondary = {} }, component = "HYDRAULIC_GASKET", branches = 2, progress = 0.6,
        hints = { [1] = "coolant_leak", [2] = "coolant_leak" }
}, {
    { { "COOLANT_LEAK_RATE", 0.02, branch = 1 }, { "COOLANT_LEAK_RATE", 0.02, branch = 2 }, hint = true },
    { { "COOLANT_LEAK_RATE", 0.08, branch = 1 }, { "COOLANT_LEAK_RATE", 0.08, branch = 2 }, hint = true },
    { { "COOLANT_LEAK_RATE", 0.25, branch = 1 }, { "COOLANT_LEAK_RATE", 0.25, branch = 2 },
        lamps = { { db.COOLANT, color.WARNING, branch = 1 }, { db.COOLANT, color.WARNING, branch = 2 } }, hint = true },
    { { "COOLANT_LEAK_RATE", 0.8, branch = 1 }, { "COOLANT_LEAK_RATE", 0.8, branch = 2 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.CRITICAL, branch = 2 } }, hint = true }
})

addBreakdown("ACCESSORY_BELT_FAILURE", {
    system = systems.COOLING, part = parts.ACCESSORY_BELT_KIT, isApplicable = getHasEngineBelt,
        causes = { primary = { "ohf", "crf" }, secondary = { "ltf", "vf" } }, component = "DRIVE_BELT", progress = 1.1
}, {
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.2 }, { "RADIATOR_HEALTH_MODIFIER", -0.2 }, { "BELT_SQUEAL_NOISE_EFFECT", 0.3 } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.5 }, { "RADIATOR_HEALTH_MODIFIER", -0.4 }, { "BELT_SQUEAL_NOISE_EFFECT", 0.5 },
        lamps = { { db.BATTERY, color.WARNING }, { db.COOLANT, color.WARNING } } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -0.7 }, { "RADIATOR_HEALTH_MODIFIER", -0.6 }, { "BELT_SQUEAL_NOISE_EFFECT", 0.8 },
        lamps = { { db.BATTERY, color.CRITICAL }, { db.COOLANT, color.CRITICAL } } },
    { { "ALTERNATOR_HEALTH_MODIFIER", -1.0 }, { "RADIATOR_HEALTH_MODIFIER", -0.85 },
        lamps = { { db.BATTERY, color.CRITICAL }, { db.COOLANT, color.CRITICAL } } }
})

addBreakdown("FAN_BLADE_FAILURE", {
    system = systems.COOLING, part = parts.FAN_BLADE, isApplicable = getHasEngine,
        causes = { primary = {}, secondary = { "ohf", "sf" } }, component = "IMPELLER", progress = 0.9
}, {
    { { "FAN_CLUTCH_MODIFIER", -0.1 }, { "FAN_BLADE_NOISE_EFFECT", 0.3 } },
    { { "FAN_CLUTCH_MODIFIER", -0.2 }, { "FAN_BLADE_NOISE_EFFECT", 0.5 }, lamps = { { db.COOLANT, color.WARNING } } },
    { { "FAN_CLUTCH_MODIFIER", -0.3 }, { "FAN_BLADE_NOISE_EFFECT", 0.8 }, lamps = { { db.COOLANT, color.WARNING } } },
    { { "FAN_CLUTCH_MODIFIER", -0.5 }, { "FAN_BLADE_NOISE_EFFECT", 1.0 }, renews = { "RADIATOR_CORE" },
        lamps = { { db.COOLANT, color.CRITICAL } } }
})

addBreakdown("ELECTRIC_COOLING_FAN_FAILURE", {
    system = systems.COOLING, part = parts.ELECTRIC_COOLING_FAN, isApplicable = getIsElectricVehicle,
        causes = { primary = {}, secondary = { "ohf", "sf" } }, component = "DC_MOTOR", progress = 1.2
}, {
    { { "FAN_CLUTCH_MODIFIER", -0.1 } },
    { { "FAN_CLUTCH_MODIFIER", -0.2 }, lamps = { { db.COOLANT, color.WARNING } } },
    { { "FAN_CLUTCH_MODIFIER", -0.3 }, lamps = { { db.COOLANT, color.WARNING } } },
    { { "FAN_CLUTCH_MODIFIER", -0.5 }, lamps = { { db.COOLANT, color.CRITICAL } } }
})

addBreakdown("FAN_CLUTCH_FAILURE", {
    system = systems.COOLING, part = parts.FAN_CLUTCH, isApplicable = getHasFanClutch,
        causes = { primary = {}, secondary = { "ohf", "sf" } }, component = "MAGNETIC_CLUTCH", progress = 0.9
}, {
    { { "FAN_CLUTCH_MODIFIER", -0.1 }, { "FAN_CLUTCH_NOISE_EFFECT", 0.6 } },
    { { "FAN_CLUTCH_MODIFIER", -0.2 }, { "FAN_CLUTCH_NOISE_EFFECT", 0.8 }, lamps = { { db.COOLANT, color.WARNING } } },
    { { "FAN_CLUTCH_MODIFIER", -0.3 }, { "FAN_CLUTCH_NOISE_EFFECT", 1.0 }, lamps = { { db.COOLANT, color.WARNING } } },
    { { "FAN_CLUTCH_MODIFIER", -0.5 }, lamps = { { db.COOLANT, color.CRITICAL } } }
})

addBreakdown("COOLANT_PUMP_FAILURE", {
    system = systems.COOLING, part = parts.COOLANT_PUMP, isApplicable = getIsElectricVehicle,
        causes = { primary = {}, secondary = { "ohf", "sf" } }, component = "CENTRIFUGAL_PUMP", progress = 1.2
}, {
    { { "RADIATOR_HEALTH_MODIFIER", -0.2 } },
    { { "RADIATOR_HEALTH_MODIFIER", -0.4 }, lamps = { { db.COOLANT, color.WARNING } } },
    { { "RADIATOR_HEALTH_MODIFIER", -0.6 }, lamps = { { db.COOLANT, color.CRITICAL } } },
    { { "RADIATOR_HEALTH_MODIFIER", -0.85 }, lamps = { { db.COOLANT, color.CRITICAL } } }
})

addBreakdown("THERMAL_WATER_PUMP", {
    system = systems.COOLING, part = parts.THERMAL_WATER_PUMP, isApplicable = getHasEngine,
        causes = { primary = { "sf" }, secondary = {} }, component = "ENGINE_WATER_PUMP", branches = 3, progress = 1.2,
        hints = { [2] = "thermal_water_pump" }
}, {
    { { "RADIATOR_HEALTH_MODIFIER", -0.2 }, { "COOLANT_LEAK_RATE", 0.02, branch = 2 }, hint = true },
    { { "RADIATOR_HEALTH_MODIFIER", -0.4 }, { "COOLANT_LEAK_RATE", 0.08, branch = 2 },
        { "WATER_PUMP_BEARING_NOISE_EFFECT", 0.5, branch = 3 }, lamps = { { db.COOLANT, color.WARNING } }, hint = true },
    { { "RADIATOR_HEALTH_MODIFIER", -0.6 }, { "COOLANT_LEAK_RATE", 0.25, branch = 2 },
        { "WATER_PUMP_BEARING_NOISE_EFFECT", 0.8, branch = 3 }, lamps = { { db.COOLANT, color.CRITICAL } }, hint = true },
    { { "RADIATOR_HEALTH_MODIFIER", -0.85 }, { "COOLANT_LEAK_RATE", 0.8, branch = 2 },
        { "WATER_PUMP_BEARING_NOISE_EFFECT", 1.0, branch = 3 }, lamps = { { db.COOLANT, color.CRITICAL } }, hint = true }
})

addBreakdown("RADIATOR_CORE", {
    system = systems.COOLING, part = parts.RADIATOR_CORE, isApplicable = always,
        causes = { primary = { "sf" }, secondary = {} }, component = "HEAT_EXCHANGER", branches = 2, progress = 0.6,
        hints = { [2] = "radiator_core" }
}, {
    { { "RADIATOR_HEALTH_MODIFIER", -0.2, branch = 1 }, { "COOLANT_LEAK_RATE", 0.02, branch = 2 }, hint = true },
    { { "RADIATOR_HEALTH_MODIFIER", -0.4, branch = 1 }, { "COOLANT_LEAK_RATE", 0.08, branch = 2 }, hint = true },
    { { "RADIATOR_HEALTH_MODIFIER", -0.6, branch = 1 }, { "COOLANT_LEAK_RATE", 0.25, branch = 2 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.WARNING, branch = 2 } }, hint = true },
    { { "RADIATOR_HEALTH_MODIFIER", -0.85, branch = 1 }, { "COOLANT_LEAK_RATE", 0.8, branch = 2 },
        lamps = { { db.COOLANT, color.CRITICAL, branch = 1 }, { db.COOLANT, color.CRITICAL, branch = 2 } }, hint = true }
})

addBreakdown("FUEL_PUMP_MALFUNCTION", {
    system = systems.FUEL, part = parts.FUEL_PUMP, isApplicable = getHasDieselFuelSystem,
        causes = { primary = {}, secondary = { "sf" } }, component = "CENTRIFUGAL_PUMP", progress = 1.1
}, {
    { { "IDLE_HUNTING_EFFECT", 0.05, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.05 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.15 }, { "ENGINE_HARD_START_MODIFIER", 2 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } } },
    { { "IDLE_HUNTING_EFFECT", 0.08, { period = 1600, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.12 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.4 }, { "ENGINE_STALLS_CHANCE", 20.0 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "EXHAUST_UNBURNT", 0.2 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING, getIsAtFullLoad, false } } },
    { { "IDLE_HUNTING_EFFECT", 0.1, { period = 1500, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.25 },
        { "FUEL_CONSUMPTION_MODIFIER", 1.0 }, { "ENGINE_STALLS_CHANCE", 10.0 }, { "ENGINE_HARD_START_MODIFIER", 6 },
        { "EXHAUST_UNBURNT", 0.3 }, { "EXHAUST_SOOT", 0.15 },
        { "ENGINE_HESITATION_CHANCE", 0.15, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("FUEL_INJECTOR_MALFUNCTION", {
    system = systems.FUEL, part = parts.FUEL_INJECTORS, isApplicable = getHasDieselFuelSystem,
        causes = { primary = {}, secondary = {} }, component = "SOLENOID_VALVE", progress = 1.1
}, {
    { { "IDLE_HUNTING_EFFECT", 0.05, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.08 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.1 }, { "EXHAUST_SOOT", 0.2 }, { "EXHAUST_UNBURNT", 0.15 },
        { "ENGINE_HESITATION_CHANCE", 0.4, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        { "INJECTOR_KNOCK_NOISE_EFFECT", 0.3 } },
    { { "IDLE_HUNTING_EFFECT", 0.08, { period = 1500, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.2 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.25 }, { "ENGINE_STALLS_CHANCE", 30.0 }, { "EXHAUST_SOOT", 0.4 },
        { "EXHAUST_UNBURNT", 0.3 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.8, cruiseState = 0, duration = 400, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        { "INJECTOR_KNOCK_NOISE_EFFECT", 0.5 }, lamps = { { db.ENGINE, color.WARNING } } },
    { { "IDLE_HUNTING_EFFECT", 0.1, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.35 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.5 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "EXHAUST_SOOT", 0.7 },
        { "EXHAUST_UNBURNT", 0.5 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        { "INJECTOR_KNOCK_NOISE_EFFECT", 0.8 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), { "INJECTOR_KNOCK_NOISE_EFFECT", 1.0 }, lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("HIGH_PRESSURE_PUMP_MALFUNCTION", {
    system = systems.FUEL, part = parts.HIGH_PRESSURE_PUMP, isApplicable = getHasHighPressurePump,
        causes = { primary = { "sf" }, secondary = {} }, component = "HIGH_PRESSURE_INJECTION_BUDGET", progress = 1.1
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "ENGINE_HARD_START_MODIFIER", 2 }, { "HIGH_PRESSURE_PUMP_NOISE_EFFECT", 0.3 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.15 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        { "HIGH_PRESSURE_PUMP_NOISE_EFFECT", 0.5 }, lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        { "HIGH_PRESSURE_PUMP_NOISE_EFFECT", 0.8 }, lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), { "HIGH_PRESSURE_PUMP_NOISE_EFFECT", 1.0 }, lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("FUEL_FILTER_CLOGGING", {
    system = systems.FUEL, part = parts.FUEL_FILTER, isApplicable = getHasDieselFuelSystem
}, {
    { { "ENGINE_HESITATION_CHANCE", 0.4, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.03 }, progressMultiplier = 0.0 },
    { { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.7, cruiseState = 0, duration = 400, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.06 }, { "ENGINE_STALLS_CHANCE", 30.0 }, { "EXHAUST_UNBURNT", 0.15 },
        progressMultiplier = 0.0 },
    { { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 0.7, cruiseState = 0, duration = 500, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "ENGINE_STALLS_CHANCE", 20.0 }, { "EXHAUST_UNBURNT", 0.25 },
        { "EXHAUST_SOOT", 0.15 }, progressMultiplier = 0.0 },
    { stopEngine({ starter = true }) }
})

addBreakdown("FUEL_LINE_AIR_LEAK", {
    system = systems.FUEL, part = parts.FUEL_LINE, isApplicable = getHasDieselFuelSystem,
        causes = { primary = {}, secondary = { "sf" } }, component = "O_RING", branches = 2, progress = 0.8
}, {
    { { "ENGINE_HARD_START_MODIFIER", 1, branch = 1 }, { "ENGINE_STALLS_CHANCE", 40.0, branch = 2 } },
    { { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.5, status = "IDLE", timer = 0 }, branch = 1 },
        { "ENGINE_HARD_START_MODIFIER", 2, branch = 1 }, { "ENGINE_STALLS_CHANCE", 20.0, branch = 1 },
        { "EXHAUST_UNBURNT", 0.2, branch = 1 }, { "ENGINE_STALLS_CHANCE", 20.0, branch = 2 } },
    { { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 0.7, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 }, branch = 1 },
        { "ENGINE_HARD_START_MODIFIER", 3, branch = 1 }, { "ENGINE_STALLS_CHANCE", 10.0, branch = 1 },
        { "EXHAUST_UNBURNT", 0.35, branch = 1 }, { "ENGINE_STALLS_CHANCE", 10.0, branch = 2 } },
    { { "ENGINE_FAILURE", 1.0, { disableAi = true, reason = "BREAKDOWN", starter = true }, branch = 1 },
        { "ENGINE_FAILURE", 1.0, { disableAi = true, reason = "BREAKDOWN", starter = true }, branch = 2 } }
})

addBreakdown("MECHANICAL_INJECTION_PUMP_MALFUNCTION", {
    system = systems.FUEL, part = parts.MECHANICAL_INJECTION_PUMP, isApplicable = getHasInjectionPump,
        causes = { primary = { "sf" }, secondary = {} }, component = "LUBRICATOR_PUMP", progress = 1.1
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "ENGINE_HARD_START_MODIFIER", 2 }, { "INJECTOR_KNOCK_NOISE_EFFECT", 0.3 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.15 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        { "INJECTOR_KNOCK_NOISE_EFFECT", 0.5 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        { "INJECTOR_KNOCK_NOISE_EFFECT", 0.8 } },
    { stopEngine({ starter = true }), { "INJECTOR_KNOCK_NOISE_EFFECT", 1.0 } }
})

addBreakdown("FUEL_METERING_VALVE_FAILURE", {
    system = systems.FUEL, part = parts.FUEL_METERING_VALVE, isApplicable = getHasCommonRail,
        causes = { primary = { "sf" }, secondary = {} }, component = "HIGH_PRESSURE_INJECTION_BUDGET", progress = 1.1
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "ENGINE_HARD_START_MODIFIER", 2 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.15 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("RAIL_PRESSURE_SENSOR_FAILURE", {
    system = systems.FUEL, part = parts.RAIL_PRESSURE_SENSOR, isApplicable = getHasCommonRail,
        causes = { primary = { "sf" }, secondary = {} }, component = "HIGH_PRESSURE_INJECTION_BUDGET", progress = 1.1
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "ENGINE_HARD_START_MODIFIER", 2 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.15 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.CRITICAL } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("RAIL_PRESSURE_LIMITER_FAILURE", {
    system = systems.FUEL, part = parts.RAIL_PRESSURE_LIMITER, isApplicable = getHasCommonRail,
        causes = { primary = { "sf" }, secondary = {} }, component = "RELIEF_VALVE", progress = 1.1
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "ENGINE_HARD_START_MODIFIER", 2 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.15 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("GAS_PRESSURE_REGULATOR_FAILURE", {
    system = systems.FUEL, part = parts.GAS_PRESSURE_REGULATOR, isApplicable = getBurnsMethane,
        causes = { primary = { "sf" }, secondary = {} }, component = "RUBBER_DIAPHRAGM", progress = 1.1
}, {
    { { "ENGINE_TORQUE_MODIFIER", -0.05 }, { "ENGINE_HARD_START_MODIFIER", 2 } },
    { { "ENGINE_TORQUE_MODIFIER", -0.15 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "ENGINE_TORQUE_MODIFIER", -0.3 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "ENGINE_STALLS_CHANCE", 10.0 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("GAS_SHUTOFF_SOLENOID_FAILURE", {
    system = systems.FUEL, part = parts.GAS_SHUTOFF_SOLENOID, isApplicable = getBurnsMethane,
        causes = { primary = {}, secondary = { "sf" } }, component = "SOLENOID_VALVE", progress = 1.1
}, {
    { { "ENGINE_HARD_START_MODIFIER", 2 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.8, status = "IDLE", timer = 0 } } },
    { { "ENGINE_STALLS_CHANCE", 20.0 }, { "ENGINE_HARD_START_MODIFIER", 4 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 400, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING, getIsAtFullLoad, false } } },
    { { "ENGINE_STALLS_CHANCE", 10.0 }, { "ENGINE_HARD_START_MODIFIER", 6 },
        { "ENGINE_HESITATION_CHANCE", 0.15, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("GAS_FILTER_CLOGGING", {
    system = systems.FUEL, part = parts.GAS_FILTER, isApplicable = getBurnsMethane,
        causes = { primary = {}, secondary = { "sf" } }, component = "FILTER_STRAINER", progress = 0.35
}, {
    { { "ENGINE_HESITATION_CHANCE", 0.4, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.03 } },
    { { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.7, cruiseState = 0, duration = 400, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.06 }, { "ENGINE_STALLS_CHANCE", 30.0 }, { "EXHAUST_UNBURNT", 0.15 } },
    { { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 0.7, cruiseState = 0, duration = 500, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        { "ENGINE_TORQUE_MODIFIER", -0.1 }, { "ENGINE_STALLS_CHANCE", 20.0 }, { "EXHAUST_UNBURNT", 0.25 },
        { "EXHAUST_SOOT", 0.15 } },
    { stopEngine({ starter = true }) }
})

addBreakdown("GAS_LINE_LEAK", {
    system = systems.FUEL, part = parts.GAS_LINES, isApplicable = getBurnsMethane,
        causes = { primary = {}, secondary = { "sf" } }, component = "O_RING", progress = 0.8
}, {
    { { "ENGINE_HARD_START_MODIFIER", 1 }, { "GAS_LEAK_NOISE_EFFECT", 0.3 } },
    { { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.5, status = "IDLE", timer = 0 } },
        { "ENGINE_HARD_START_MODIFIER", 2 }, { "ENGINE_STALLS_CHANCE", 20.0 }, { "EXHAUST_UNBURNT", 0.2 },
        { "GAS_LEAK_NOISE_EFFECT", 0.5 } },
    { { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 0.7, cruiseState = 0, duration = 500, motorLoad = 0.5, status = "IDLE", timer = 0 } },
        { "ENGINE_HARD_START_MODIFIER", 3 }, { "ENGINE_STALLS_CHANCE", 10.0 }, { "EXHAUST_UNBURNT", 0.35 },
        { "GAS_LEAK_NOISE_EFFECT", 0.8 } },
    { stopEngine({ starter = true }), { "GAS_LEAK_NOISE_EFFECT", 1.0 } }
})

addBreakdown("GAS_INJECTOR_MALFUNCTION", {
    system = systems.FUEL, part = parts.GAS_INJECTORS, isApplicable = getBurnsMethane,
        causes = { primary = {}, secondary = {} }, component = "SOLENOID_VALVE", progress = 1.1
}, {
    { { "IDLE_HUNTING_EFFECT", 0.05, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.08 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.1 }, { "EXHAUST_SOOT", 0.2 }, { "EXHAUST_UNBURNT", 0.15 },
        { "ENGINE_HESITATION_CHANCE", 0.4, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.9, status = "IDLE", timer = 0 } } },
    { { "IDLE_HUNTING_EFFECT", 0.08, { period = 1500, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.2 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.25 }, { "ENGINE_STALLS_CHANCE", 30.0 }, { "EXHAUST_SOOT", 0.4 },
        { "EXHAUST_UNBURNT", 0.3 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.8, cruiseState = 0, duration = 400, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.WARNING } } },
    { { "IDLE_HUNTING_EFFECT", 0.1, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.35 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.5 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "EXHAUST_SOOT", 0.7 },
        { "EXHAUST_UNBURNT", 0.5 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.CRITICAL } } },
    { stopEngine({ starter = true }), lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("SPARK_PLUG_WEAR", {
    system = systems.ELECTRICAL, part = parts.SPARK_PLUGS, isApplicable = getBurnsMethane
}, {
    { { "IDLE_HUNTING_EFFECT", 0.05, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.08 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.1 }, { "EXHAUST_UNBURNT", 0.15 },
        { "ENGINE_HESITATION_CHANCE", 0.4, { amplitude = 0.6, cruiseState = 0, duration = 300, motorLoad = 0.9, status = "IDLE", timer = 0 } },
        progressMultiplier = 0 },
    { { "IDLE_HUNTING_EFFECT", 0.08, { period = 1500, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.2 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.25 }, { "ENGINE_STALLS_CHANCE", 30.0 }, { "EXHAUST_UNBURNT", 0.3 },
        { "ENGINE_HESITATION_CHANCE", 0.3, { amplitude = 0.8, cruiseState = 0, duration = 400, motorLoad = 0.8, status = "IDLE", timer = 0 } },
        progressMultiplier = 0, lamps = { { db.ENGINE, color.WARNING } } },
    { { "IDLE_HUNTING_EFFECT", 0.1, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.35 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.5 }, { "ENGINE_HARD_START_MODIFIER", 6 }, { "EXHAUST_UNBURNT", 0.5 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        progressMultiplier = 0, lamps = { { db.ENGINE, color.CRITICAL } } },
    { { "IDLE_HUNTING_EFFECT", 0.1, { period = 1800, timer = 0 } }, { "ENGINE_TORQUE_MODIFIER", -0.35 },
        { "FUEL_CONSUMPTION_MODIFIER", 0.5 }, { "ENGINE_HARD_START_MODIFIER", 12 }, { "ENGINE_STALLS_CHANCE", 30.0 },
        { "EXHAUST_UNBURNT", 0.5 },
        { "ENGINE_HESITATION_CHANCE", 0.2, { amplitude = 1.0, cruiseState = 0, duration = 500, motorLoad = 0.7, status = "IDLE", timer = 0 } },
        lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("ADBLUE_PUMP_FAILURE", {
    system = systems.FUEL, part = parts.ADBLUE_PUMP, isApplicable = isAdBlueApplicable,
        causes = { primary = {}, secondary = { "sf" } }, component = "ADBLUE_MODULE_SERVICE_PROXY"
}, {
    { { "SCR_DOSING_FAILURE", 1 }, progressMultiplier = 2.0, lamps = { { db.ENGINE, color.WARNING } } }
})

addBreakdown("ADBLUE_DOSER_FAILURE", {
    system = systems.FUEL, part = parts.ADBLUE_DOSER, isApplicable = isAdBlueApplicable,
        causes = { primary = {}, secondary = {} }, component = "ADBLUE_DOSER_SERVICE_PROXY"
}, {
    { { "SCR_DOSING_FAILURE", 1 }, progressMultiplier = 2.0, lamps = { { db.ENGINE, color.WARNING } } }
})

addBreakdown("ADBLUE_FILTER_CLOGGING", {
    system = systems.FUEL, part = parts.ADBLUE_FILTER, isApplicable = isAdBlueApplicable
}, {
    { progressMultiplier = 0 },
    { progressMultiplier = 0, lamps = { { db.ENGINE, color.WARNING } } },
    { { "SCR_DOSING_FAILURE", 1 }, progressMultiplier = 0, lamps = { { db.ENGINE, color.WARNING } } },
    { { "SCR_DOSING_FAILURE", 1 }, lamps = { { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("NOX_SENSOR_FAILURE", {
    system = systems.FUEL, part = parts.NOX_SENSOR, isApplicable = isAdBlueApplicable,
        causes = { primary = { "sf" }, secondary = {} }, component = "NOX_TRANSDUCER_PROXY"
}, {
    { { "NOX_MONITORING_FAILURE", 1 }, progressMultiplier = 2.0, lamps = { { db.ENGINE, color.WARNING } } }
})

addBreakdown("PARTICULATE_FILTER_FAILURE", {
    system = systems.FUEL, part = parts.PARTICULATE_FILTER, isApplicable = getHasParticulateFilter,
        causes = { primary = {}, secondary = {} }, component = "DPF_FILTER_STRAINER_PROXY", branches = 2
}, {
    { { "EXHAUST_SOOT", 0.2, branch = 1 } },
    { { "EXHAUST_SOOT", 0.4, branch = 1 }, lamps = { { db.DPF, color.WARNING } } },
    { { "EXHAUST_SOOT", 0.7, branch = 1 }, { "PARTICULATE_FILTER_BLOCKED", 1, branch = 2 },
        lamps = { { db.DPF, color.WARNING } } },
    { { "EXHAUST_SOOT", 0.7, branch = 1 }, { "PARTICULATE_FILTER_BLOCKED", 1, branch = 2 },
        lamps = { { db.DPF, color.CRITICAL } } }
})

addBreakdown("PARTICULATE_FILTER_SOOT_OVERLOAD", {
    isSelectable = false, system = systems.FUEL, part = parts.PARTICULATE_FILTER, isApplicable = getHasParticulateFilter
}, {
    { severity = MAJOR, description = "rms_breakdowns_particulate_filter_soot_overload_stage1_description",
        detectionChance = 1.0, lamps = { { db.DPF, color.WARNING }, { db.ENGINE, color.WARNING } } },
    { severity = CRITICAL, description = "rms_breakdowns_particulate_filter_soot_overload_stage2_description",
        detectionChance = 1.0, lamps = { { db.DPF, color.CRITICAL }, { db.ENGINE, color.CRITICAL } } }
})

addBreakdown("TRACTION_BATTERY_CELL_FAULT", {
    system = systems.FUEL, part = parts.TRACTION_BATTERY, isApplicable = getIsElectricVehicle,
        causes = { primary = { "ddf", "bhf" }, secondary = { "hdf" } }, component = "TRACTION_BATTERY", progress = 1.4
}, {
    { { "TRACTION_BATTERY_CAPACITY_MODIFIER", -0.05 } },
    { { "TRACTION_BATTERY_CAPACITY_MODIFIER", -0.12 }, { "ENGINE_TORQUE_MODIFIER", -0.1 },
        lamps = { { db.TRACTION_BATTERY, color.WARNING } } },
    { { "TRACTION_BATTERY_CAPACITY_MODIFIER", -0.25 }, { "ENGINE_TORQUE_MODIFIER", -0.25 },
        { "ENGINE_STALLS_CHANCE", 15.0 }, lamps = { { db.TRACTION_BATTERY, color.CRITICAL } } },
    { { "TRACTION_BATTERY_CAPACITY_MODIFIER", -0.25 }, stopEngine(),
        lamps = { { db.TRACTION_BATTERY, color.CRITICAL }, { db.WARNING, color.CRITICAL } } }
})

addBreakdown("HV_CONTACTOR_FAILURE", {
    system = systems.FUEL, part = parts.HV_CONTACTOR, isApplicable = getIsElectricVehicle,
        causes = { primary = { "hdf" }, secondary = {} }, component = "CIRCUIT_BREAKER", progress = 1.1
}, {
    { { "ENGINE_STALLS_CHANCE", 60.0 } },
    { { "ENGINE_STALLS_CHANCE", 30.0 }, lamps = { { db.TRACTION_BATTERY, color.WARNING } } },
    { { "ENGINE_STALLS_CHANCE", 10.0 }, lamps = { { db.TRACTION_BATTERY, color.CRITICAL } } },
    { stopEngine(), lamps = { { db.TRACTION_BATTERY, color.CRITICAL } } }
})

local function isHarvestRunning(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.isHarvestRunning == true
end

local function forHarvestKinds(...)
    local kinds = {}
    for _, kind in ipairs({...}) do
        kinds[kind] = true
    end
    return function(vehicle)
        return kinds[RMS_Drivetrain.getHarvestKind(vehicle)] == true
    end
end

local isAnyHarvester = forHarvestKinds("grain", "forage", "beet", "potato", "cotton", "sugarcane", "grape", "vegetable")
local isGrainHarvester = forHarvestKinds("grain")
local isForageHarvester = forHarvestKinds("forage")
local isBeetHarvester = forHarvestKinds("beet")
local isRootHarvester = forHarvestKinds("beet", "potato")
local isPotatoHarvester = forHarvestKinds("potato")
local isCottonHarvester = forHarvestKinds("cotton")
local isSugarcaneHarvester = forHarvestKinds("sugarcane")
local isGrapeHarvester = forHarvestKinds("grape")
local isVegetableHarvester = forHarvestKinds("vegetable")

-- an attached beet head carries the topper and the shares itself
local function isBeetHeadOrgan(vehicle)
    return isBeetHarvester(vehicle) and vehicle.spec_cutter ~= nil
end

local function isLiftingShareOrgan(vehicle)
    return isRootHarvester(vehicle) and vehicle.spec_cutter ~= nil
end

local function isStrawChopperOrgan(vehicle)
    return isGrainHarvester(vehicle) and vehicle.spec_combine.chopper.isAvailable == true
end

local function getHarvestSymptoms(profile)
    local function throughput(value) return { "HARVEST_THROUGHPUT_LIMIT", value } end
    -- value is the mean time between two blockages, in minutes
    local function blockage(minutes) return { "HARVEST_BLOCKAGE_CHANCE", minutes, { status = "IDLE" } } end
    local function grainLoss(value) return { "HARVEST_GRAIN_LOSS", value } end
    local function powerDemand(value) return { "HARVEST_POWER_DEMAND", value } end
    local function bearingNoise(value) return { "HARVEST_BEARING_NOISE_EFFECT", value } end
    local function stop() return { "HARVEST_FAILURE", 1.0, { disableAi = true } } end

    if profile == "feed" then
        return { { throughput(0.10) }, { throughput(0.15), blockage(30) }, { throughput(0.25), blockage(10) }, { stop() } }
    elseif profile == "loss" then
        return { { grainLoss(0.01) }, { grainLoss(0.02) }, { grainLoss(0.04), blockage(20) }, { stop() } }
    elseif profile == "flow" then
        return { { throughput(0.10) }, { throughput(0.15), grainLoss(0.01) }, { throughput(0.25), blockage(10) }, { stop() } }
    elseif profile == "chopper" then
        return { { powerDemand(0.03) }, { powerDemand(0.06) }, { powerDemand(0.10) }, { { "CHOPPER_FAILURE", 1.0 } } }
    elseif profile == "cutting" then
        return { { powerDemand(0.05) }, { powerDemand(0.10) }, { powerDemand(0.15), blockage(20) }, { stop() } }
    elseif profile == "blower" then
        return { { throughput(0.05) }, { blockage(30) }, { blockage(10), grainLoss(0.01) }, { stop() } }
    elseif profile == "drive" then
        return { { throughput(0.05) }, { blockage(30) }, { throughput(0.15), blockage(10) }, { stop() } }
    elseif profile == "bearing" then
        return { { bearingNoise(0.7) }, { bearingNoise(1.2) }, { bearingNoise(1.7) }, { bearingNoise(1.7), stop() } }
    elseif profile == "detector" then
        return { { blockage(30) }, { blockage(10) }, { { "METAL_DETECTOR_OFF", 1.0 } } }
    end
    return { { grainLoss(0.01) }, { grainLoss(0.02), powerDemand(0.05) }, { grainLoss(0.04), powerDemand(0.10) }, { stop() } }
end

-- def={part, isApplicable, component, causes, symptoms, texts, progress}
local function addHarvestOrgan(id, def)
    local stages = getHarvestSymptoms(def.symptoms)
    for index = 2, #stages do
        stages[index].lamps = { { db.WARNING, index == 2 and color.WARNING or color.CRITICAL } }
    end
    addBreakdown(id, { system = systems.HARVEST, part = def.part, isApplicable = def.isApplicable, isCanProgress = isHarvestRunning,
        causes = def.causes, component = def.component, texts = def.texts, progress = def.progress }, stages)
end

local function causes(primary, secondary)
    table.insert(primary, 1, "hef")
    return { primary = primary, secondary = secondary or {} }
end

addHarvestOrgan("HARVEST_DRIVE_BELT_WEAR", { part = parts.HARVEST_DRIVE_BELTS, isApplicable = isAnyHarvester, component = "DRIVE_BELT",
    causes = causes({ "hwf" }), symptoms = "drive", texts = "harvest_drive_belt_wear" })
addHarvestOrgan("HARVEST_DRIVE_BEARING_WEAR", { part = parts.HARVEST_DRIVE_BEARINGS, isApplicable = isAnyHarvester, component = "ROLLER_BEARING",
    causes = causes({ "lubf" }), symptoms = "bearing", texts = "harvest_drive_bearing_wear", progress = 1.2 })

addHarvestOrgan("FEEDER_CHAIN_WEAR", { part = parts.FEEDER_CHAIN, isApplicable = isGrainHarvester, component = "FEEDER_CHAIN",
    causes = causes({ "hstf", "lubf" }), symptoms = "feed", texts = "feeder_chain_wear" })
addHarvestOrgan("FEED_ACCELERATOR_WEAR", { part = parts.FEED_ACCELERATOR, isApplicable = isGrainHarvester, component = "FEED_ACCELERATOR",
    causes = causes({ "hstf" }), symptoms = "feed", texts = "feed_accelerator_wear" })
addHarvestOrgan("THRESHING_BAR_WEAR", { part = parts.THRESHING_BARS, isApplicable = isGrainHarvester, component = "THRESHING_BARS",
    causes = causes({ "hstf", "hrf" }), symptoms = "loss", texts = "threshing_bar_wear" })
addHarvestOrgan("CONCAVE_WEAR", { part = parts.CONCAVE, isApplicable = isGrainHarvester, component = "CONCAVE",
    causes = causes({ "hstf", "hrf" }), symptoms = "loss", texts = "concave_wear" })
addHarvestOrgan("SEPARATION_WEAR", { part = parts.SEPARATION, isApplicable = isGrainHarvester, component = "SEPARATION_ELEMENTS",
    causes = causes({ "hwf" }), symptoms = "loss", texts = "separation_wear" })
addHarvestOrgan("CLEANING_SIEVE_WEAR", { part = parts.CLEANING_SIEVES, isApplicable = isGrainHarvester, component = "CLEANING_SIEVES",
    causes = causes({}, { "hwf" }), symptoms = "loss", texts = "cleaning_sieve_wear" })
addHarvestOrgan("GRAIN_ELEVATOR_WEAR", { part = parts.GRAIN_ELEVATORS, isApplicable = isGrainHarvester, component = "GRAIN_ELEVATOR",
    causes = causes({ "hgf" }, { "lubf" }), symptoms = "flow", texts = "grain_elevator_wear" })
addHarvestOrgan("STRAW_CHOPPER_WEAR", { part = parts.STRAW_CHOPPER, isApplicable = isStrawChopperOrgan, component = "STRAW_CHOPPER_KNIVES",
    causes = causes({ "hsf", "hwf" }, { "hstf" }), symptoms = "chopper", texts = "straw_chopper_wear" })

addHarvestOrgan("FEED_ROLL_WEAR", { part = parts.FEED_ROLLS, isApplicable = isForageHarvester, component = "FEED_ROLLS",
    causes = causes({ "hstf" }), symptoms = "feed", texts = "feed_roll_wear" })
addHarvestOrgan("METAL_DETECTOR_FAILURE", { part = parts.METAL_DETECTOR, isApplicable = isForageHarvester, component = "TRANSDUCER",
    causes = causes({}), symptoms = "detector", texts = "metal_detector_failure" })
addHarvestOrgan("CUTTERHEAD_WEAR", { part = parts.CUTTERHEAD, isApplicable = isForageHarvester, component = "CUTTERHEAD",
    causes = causes({ "hstf" }), symptoms = "cutting", texts = "cutterhead_wear" })
addHarvestOrgan("FORAGE_KNIFE_WEAR", { part = parts.FORAGE_KNIVES, isApplicable = isForageHarvester, component = "FORAGE_KNIVES",
    causes = causes({ "hstf" }), symptoms = "cutting", texts = "forage_knife_wear" })
addHarvestOrgan("SHEAR_BAR_WEAR", { part = parts.SHEAR_BAR, isApplicable = isForageHarvester, component = "SHEAR_BAR",
    causes = causes({ "hstf" }), symptoms = "cutting", texts = "shear_bar_wear" })
addHarvestOrgan("CROP_PROCESSOR_WEAR", { part = parts.CROP_PROCESSOR, isApplicable = isForageHarvester, component = "CROP_PROCESSOR",
    causes = causes({ "hgf" }), symptoms = "cutting", texts = "crop_processor_wear" })
addHarvestOrgan("CROP_ACCELERATOR_WEAR", { part = parts.CROP_ACCELERATOR, isApplicable = isForageHarvester, component = "CROP_ACCELERATOR",
    causes = causes({ "hgf" }), symptoms = "blower", texts = "crop_accelerator_wear" })
addHarvestOrgan("DISCHARGE_SPOUT_WEAR", { part = parts.DISCHARGE_SPOUT, isApplicable = isForageHarvester, component = "DISCHARGE_SPOUT",
    causes = causes({ "hgf" }), symptoms = "blower", texts = "discharge_spout_wear" })

addHarvestOrgan("BEET_TOPPER_WEAR", { part = parts.BEET_TOPPER, isApplicable = isBeetHeadOrgan, component = "STRAW_CHOPPER_KNIVES",
    causes = causes({ "hstf" }), symptoms = "loss", texts = "harvest_pickup_wear" })
addHarvestOrgan("LIFTING_SHARE_WEAR", { part = parts.LIFTING_SHARES, isApplicable = isLiftingShareOrgan, component = "SEPARATION_ELEMENTS",
    causes = causes({ "hstf" }), symptoms = "shares", texts = "lifting_share_wear" })
addHarvestOrgan("BEET_CLEANING_WEAR", { part = parts.BEET_CLEANING, isApplicable = isBeetHarvester, component = "CONCAVE",
    causes = causes({ "hstf" }, { "hwf" }), symptoms = "loss", texts = "harvest_cleaning_wear" })
addHarvestOrgan("ROOT_ELEVATOR_WEAR", { part = parts.ROOT_ELEVATOR, isApplicable = isBeetHarvester, component = "FEEDER_CHAIN",
    causes = causes({ "hstf" }, { "lubf" }), symptoms = "feed", texts = "harvest_conveyor_wear" })
addHarvestOrgan("HOPPER_FLOOR_WEAR", { part = parts.HOPPER_FLOOR, isApplicable = isRootHarvester, component = "GRAIN_ELEVATOR",
    causes = causes({}, { "lubf" }), symptoms = "flow", texts = "harvest_unloading_wear" })
addHarvestOrgan("SIEVE_WEB_WEAR", { part = parts.SIEVE_WEBS, isApplicable = isPotatoHarvester, component = "FEEDER_CHAIN",
    causes = causes({ "hstf" }, { "lubf" }), symptoms = "feed", texts = "harvest_conveyor_wear" })
addHarvestOrgan("HAULM_SEPARATOR_WEAR", { part = parts.HAULM_SEPARATOR, isApplicable = isPotatoHarvester, component = "CONCAVE",
    causes = causes({ "hstf" }, { "hwf" }), symptoms = "loss", texts = "harvest_cleaning_wear" })

addHarvestOrgan("PICKING_UNIT_WEAR", { part = parts.PICKING_UNITS, isApplicable = isCottonHarvester, component = "FORAGE_KNIVES",
    causes = causes({}), symptoms = "loss", texts = "harvest_pickup_wear" })
addHarvestOrgan("SPINDLE_MOISTENER_WEAR", { part = parts.SPINDLE_MOISTENER, isApplicable = isCottonHarvester, component = "DRIVE_BELT",
    causes = causes({}), symptoms = "loss", texts = "harvest_pickup_wear" })
addHarvestOrgan("COTTON_FAN_WEAR", { part = parts.COTTON_FAN, isApplicable = isCottonHarvester, component = "CLEANING_SIEVES",
    causes = causes({}), symptoms = "loss", texts = "harvest_cleaning_wear" })
addHarvestOrgan("MODULE_BUILDER_WEAR", { part = parts.MODULE_BUILDER, isApplicable = isCottonHarvester, component = "DRIVE_BELT",
    causes = causes({}), symptoms = "flow", texts = "harvest_unloading_wear" })

addHarvestOrgan("BASE_CUTTER_WEAR", { part = parts.BASE_CUTTERS, isApplicable = isSugarcaneHarvester, component = "FORAGE_KNIVES",
    causes = causes({ "hstf" }), symptoms = "cutting", texts = "forage_knife_wear" })
addHarvestOrgan("CANE_FEED_ROLL_WEAR", { part = parts.CANE_FEED_ROLLS, isApplicable = isSugarcaneHarvester, component = "FEED_ROLLS",
    causes = causes({ "hstf" }), symptoms = "feed", texts = "feed_roll_wear" })
addHarvestOrgan("CANE_CHOPPER_WEAR", { part = parts.CANE_CHOPPER, isApplicable = isSugarcaneHarvester, component = "FORAGE_KNIVES",
    causes = causes({}), symptoms = "cutting", texts = "forage_knife_wear" })
addHarvestOrgan("CANE_EXTRACTOR_WEAR", { part = parts.CANE_EXTRACTOR, isApplicable = isSugarcaneHarvester, component = "CROP_ACCELERATOR",
    causes = causes({}), symptoms = "loss", texts = "harvest_cleaning_wear" })
addHarvestOrgan("CANE_ELEVATOR_WEAR", { part = parts.CANE_ELEVATOR, isApplicable = isSugarcaneHarvester, component = "GRAIN_ELEVATOR",
    causes = causes({}, { "lubf" }), symptoms = "feed", texts = "harvest_conveyor_wear" })

addHarvestOrgan("SHAKER_WEAR", { part = parts.SHAKER, isApplicable = isGrapeHarvester, component = "THRESHING_BARS",
    causes = causes({}), symptoms = "loss", texts = "harvest_pickup_wear" })
addHarvestOrgan("CATCHING_SCALE_WEAR", { part = parts.CATCHING_SCALES, isApplicable = isGrapeHarvester, component = "GRAIN_ELEVATOR",
    causes = causes({}), symptoms = "loss", texts = "harvest_pickup_wear" })
addHarvestOrgan("BUCKET_CONVEYOR_WEAR", { part = parts.BUCKET_CONVEYORS, isApplicable = isGrapeHarvester, component = "GRAIN_ELEVATOR",
    causes = causes({}, { "lubf" }), symptoms = "feed", texts = "harvest_conveyor_wear" })
addHarvestOrgan("CLEANING_FAN_WEAR", { part = parts.CLEANING_FANS, isApplicable = isGrapeHarvester, component = "CLEANING_SIEVES",
    causes = causes({}), symptoms = "loss", texts = "harvest_cleaning_wear" })
addHarvestOrgan("DESTEMMER_WEAR", { part = parts.DESTEMMER, isApplicable = isGrapeHarvester, component = "CLEANING_SIEVES",
    causes = causes({}), symptoms = "loss", texts = "harvest_cleaning_wear" })

addHarvestOrgan("VEGETABLE_PICKER_WEAR", { part = parts.VEGETABLE_PICKER, isApplicable = isVegetableHarvester, component = "THRESHING_BARS",
    causes = causes({}), symptoms = "loss", texts = "harvest_pickup_wear" })
addHarvestOrgan("VEGETABLE_CLEANING_WEAR", { part = parts.VEGETABLE_CLEANING, isApplicable = isVegetableHarvester, component = "CLEANING_SIEVES",
    causes = causes({}), symptoms = "loss", texts = "harvest_cleaning_wear" })
addHarvestOrgan("VEGETABLE_ELEVATOR_WEAR", { part = parts.VEGETABLE_ELEVATORS, isApplicable = isVegetableHarvester, component = "GRAIN_ELEVATOR",
    causes = causes({}, { "lubf" }), symptoms = "feed", texts = "harvest_conveyor_wear" })
