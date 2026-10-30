-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

local LAMP_LIFE_FACTOR = 2

---RMS configuration.
RMS_Config = {
    CONFIG_VERSION = 1,

    -- extensive debug logging in the console
    DEBUG = false,
    TUTORIAL_MODE = true,

    -- update interval of the responsive effects, in ms
    ON_UPDATE_DELAY = 100, -- 10 Hz
    TUTORIAL_UPDATE_DELAY = 1000, 

    UPDATE_VEHICLE_STATE_DELAY_ONE = 50,
    UPDATE_VEHICLE_STATE_DELAY_TWO = 200,
    UPDATE_VEHICLE_STATE_DELAY_THREE = 500,
    ROOF_RAYCAST_INTERVAL = 5000,
    ROOF_RAYCAST_DISTANCE = 40,
    ROOF_RAYCAST_START_OFFSET = 1,
    ROOF_STATIONARY_SPEED_LIMIT = 0.5,
    
    -- Simulation interval (ms)
    CORE_UPDATE_DELAY = 250,
    META_UPDATE_DELAY = 30000,

    -- wear and breakdown probability
    CORE = {
        REFERENCE_SERVICE_WEAR = 0.1,
        REFERENCE_SYSTEMS_WEAR = 0.01,
        BASE_SERVICE_WEAR = 0.05,
        BASE_SYSTEMS_WEAR = 0.01,

        RAIN_FACTOR = 1.1,
        HAIL_FACTOR = 1.3,
        SNOW_FACTOR = 1.1,
        SERVICE_EXPIRED_THRESHOLD = 0.5,

        SYSTEM_WEIGHTS = {
            engine=0.22, 
            transmission=0.16, 
            hydraulics=0.12, 
            cooling=0.12, 
            electrical=0.10, 
            chassis=0.10, 
            fuel=0.08,
            pto=0.06
        },

        AVG_STRESS_WARNING_THRESHOLD = 0.22,
        AVG_STRESS_CRITICAL_THRESHOLD = 0.44,

        LUGGING_RPM_RANGE_THRESHOLD = 0.25,

        ENGINE_FACTOR_DATA = {
            MOTOR_IDLING_MULTIPLIER = 0.5,
            SERVICE_EXPIRED_MULTIPLIER = 6.0,
            MOTOR_IDLING_THRESHOLD = 0.3,
            MOTOR_OVERLOADED_MULTIPLIER = 1.5, 
            MOTOR_OVERLOADED_THRESHOLD = 1.0,
            MOTOR_OVERLOADED_MAX_EFFECT = 1.15,
            LUGGING_MULTIPLIER = 3.0,       
            LUGGING_MOTORLOAD_THRESHOLD = 0.80,
            COLD_MOTOR_RPM_INFLUENCE = 0.35,
            COLD_MOTOR_LOAD_THRESHOLD = 0.85,
            COLD_MOTOR_TEMP_THRESHOLD = 50,
            COLD_MOTOR_WARNING_EXPOSURE_MS = 2000,
            COLD_MOTOR_MULTIPLIER = 60.0,
            OVERHEAT_MOTOR_MULTIPLIER = 100.0, 
            OVERHEAT_MOTOR_THRESHOLD = 95,
            AIR_FILTER_CLOGGING_MULTIPLIER = 0.8,
            AIR_FILTER_CLOGGING_THRESHOLD = 0.5
        },

        TRANSMISSION_FACTOR_DATA = {
            TRANSMISSION_IDLING_MULTIPLIER = 0.5,
            SERVICE_EXPIRED_MULTIPLIER = 4.0,
            PULL_OVERLOAD_MULTIPLIER = 1.5,    
            PULL_OVERLOAD_THRESHOLD = 1.0,
            PULL_OVERLOAD_TIMER_THRESHOLD = 60,
            PULL_OVERLOAD_TIMER_MAX_EFFECT = 90,
            LUGGING_MULTIPLIER = 10.0,
            LUGGING_MOTORLOAD_THRESHOLD = 0.80,
            WHEEL_SLIP_MULTIPLIER = 10.0,        
            WHEEL_SLIP_THRESHOLD = 0.05,
            HEAVY_TRAILER_MULTIPLIER = 2.0,
            HEAVY_TRAILER_MASS_RATIO_THRESHOLD = 10.0,
            HEAVY_TRAILER_MASS_RATIO_FULL_EFFECT = 5.0,
            HEAVY_TRAILER_TRUCK_MASS_RATIO_THRESHOLD = 6.0,
            HEAVY_TRAILER_TRUCK_MASS_RATIO_FULL_EFFECT = 3.0,
            HEAVY_TRAILER_MOTORLOAD_THRESHOLD = 0.7,
            HEAVY_TRAILER_TUTORIAL_MARGIN = 0.8,
            COLD_TRANSMISSION_MULTIPLIER = 0.92,
            COLD_TRANSMISSION_THRESHOLD = 45,
            COLD_TRANSMISSION_LOAD_THRESHOLD = 0.60,
            OVERHEAT_TRANSMISSION_MAX_MULTIPLIER = 100.0,
            OVERHEAT_TRANSMISSION_THRESHOLD = 100,
        },

        HYDRAULICS_FACTOR_DATA = {
            SERVICE_EXPIRED_MULTIPLIER = 3.0,
            PUMP_WEAR_RATE = 0.5,
            COLD_OIL_MULTIPLIER = 0.95,
            COLD_OIL_THRESHOLD = 30,
            HOT_OIL_MULTIPLIER = 100.0,
            HOT_OIL_THRESHOLD = 90,
            VIB_FULL_LIFT_MASS_RATIO = 0.33,
            FILTER_BYPASS_STAGE = 2,
            FILTER_BYPASS_MULTIPLIER = 0.5
        },

        PTO_FACTOR_DATA = {
            SERVICE_EXPIRED_MULTIPLIER = 4.0,
            LOAD_FACTOR_THRESHOLD = 0.40,
            LOAD_FACTOR_FULL_EFFECT = 0.90,
            LOAD_FACTOR_MULTIPLIER = 6.0,
            OVERLOAD_FACTOR_FULL_EFFECT = 1.20,
            OVERLOAD_FACTOR_MULTIPLIER = 12.0,
            RAISED_IMPLEMENT_MULTIPLIER = 4.0,
            RAISED_TUTORIAL_MS = 20000,
            ENGAGEMENT_CLUTCH_DAMAGE = 0.0002,
            ENGAGEMENT_SHOCK_RPM_THRESHOLD = 0.25,
            ENGAGEMENT_SHOCK_DAMAGE = 0.005,
            ENGAGEMENT_SHOCK_MIN_SIZE = 0.25
        },

        COOLING_FACTOR_DATA = {
            COOLING_IDLING_MULTIPLIER = 0.5,
            SERVICE_EXPIRED_MULTIPLIER = 4.0,
            HIGH_COOLING_FACTOR_MULTIPLIER = 1.5,
            HIGH_COOLING_FACTOR_THRESHOLD = 0.95,
            HIGH_COOLING_TEMP_MARGIN = 3,
            OVERHEAT_FACTOR_MULTIPLIER = 50.0,
            OVERHEAT_FACTOR_THRESHOLD = 95,
            COLD_SHOCK_FACTOR_MULTIPLIER = 30.0,
            COLD_SHOCK_FACTOR_THRESHOLD = 50
        },

        ELECTRICAL_FACTOR_DATA = {
            CRANKING_STRESS_MULTIPLIER = 5.0,
            RAIN_FACTOR_MULTIPLIER = 0.8,
            SNOW_FACTOR_MULTIPLIER = 0.6,
            HAIL_FACTOR_MULTIPLIER = 1.0,
            OVERHEAT_FACTOR_MULTIPLIER = 50.0,
            OVERHEAT_FACTOR_THRESHOLD = 95,
            LIGHTS_FACTOR_MULTIPLIER = 0.2,
            VIB_FACTOR_THRESHOLD = 0.08,
            VIB_FACTOR_MAX_SIGNAL = 0.36,
            VIB_FACTOR_MULTIPLIER = 9.0
        },

        CHASSIS_FACTOR_DATA = {
            CHASSIS_IDLING_MULTIPLIER = 0.5,
            LUBRICATION_FACTOR_MULTIPLIER = 5.0,
            VIB_FACTOR_THRESHOLD = 0.08,
            VIB_FACTOR_MAX_SIGNAL = 0.36,
            VIB_FACTOR_MULTIPLIER = 36.0,
            STEER_LOAD_FACTOR_MULTIPLIER = 1.33,
            STEER_LOAD_SPEED_THRESHOLD = 4.0,
            STEER_LOAD_RATE_DEADZONE = 0.02,
            STEER_LOAD_AXLE_RATIO_MAX = 3.0,
            STEER_PLAY_KICK_GAIN = 3.0,
            STEER_PLAY_FULL_SPEED = 30.0,
            STEER_PLAY_RECENTER_TIME = 0.6,
            STEER_STOP_BLEND = 4.0,
            STEER_SHIMMY_MIN_PLAY = 2.0,
            STEER_SHIMMY_SPEED_MIN = 25.0,
            STEER_SHIMMY_SPEED_PEAK = 35.0,
            STEER_SHIMMY_SPEED_MAX = 45.0,
            STEER_SHIMMY_FREQUENCY = 6.0,
            STEER_SHIMMY_SHARE = 0.4,
            STEER_FREE_FLUTTER_ANGLE = 12.0,
            STEER_FREE_FLUTTER_SPEED_MIN = 8.0,
            STEER_FREE_FLUTTER_SPEED_MAX = 25.0,
            STEER_FREE_ARTICULATION_PLAY = 6.0,
            TERRAIN_IMPACT_MIN_SPEED_LOSS = 10.0,
            TERRAIN_IMPACT_DAMAGE_PER_KMH = 0.001,
            TERRAIN_IMPACT_MAX_DAMAGE = 0.05,
            VIB_TUTORIAL_MS = 3000,
            TERRAIN_IMPACT_TUTORIAL_MS = 5000,
            BRAKE_MASS_FACTOR_MULTIPLIER = 36.0,
            BRAKE_MASS_RATIO_THRESHOLD = 10.0,
            BRAKE_MASS_RATIO_FULL_EFFECT = 5.0,
            BRAKE_MASS_TRUCK_RATIO_THRESHOLD = 6.0,
            BRAKE_MASS_TRUCK_RATIO_FULL_EFFECT = 3.0,
            BRAKE_MASS_SPEED_THRESHOLD = 2.0,
            BRAKE_PEDAL_THRESHOLD = 0.15,
        },

        FUEL_FACTOR_DATA = {
            SERVICE_EXPIRED_MULTIPLIER = 2.0,
            LOW_FUEL_FACTOR_MULTIPLIER = 4.0,
            LOW_FUEL_THRESHOLD = 0.20,
            COLD_FUEL_THRESHOLD = 20.0,
            COLD_FUEL_FACTOR_MULTIPLIER = 50,
            IDLE_DEPOSIT_SPEED_THRESHOLD = 0.5,
            IDLE_DEPOSIT_LOAD_THRESHOLD = 0.3,
            IDLE_DEPOSIT_FACTOR_MULTIPLIER = 0.8,
            IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD = 60,
            IDLE_DEPOSIT_FACTOR_MAX_TIMER = 360,
            HIGH_PRESSURE_FACTOR_MULTIPLIER = 1.5,
            HIGH_PRESSURE_FACTOR_THRESHOLD = 0.8,
        },

        REPEAT_BREAKDOWN_TIME = 1.3 * 3600000,
        USED_VEHICLE_HISTORY = {
            DAMAGE_MIN = 0.2,
            DAMAGE_MAX = 0.6,
            LIT_SHARE = 0.5,
            BASE_RATES = { engine = 1, transmission = 1, hydraulics = 0.5, cooling = 1, electrical = 1, chassis = 1, fuel = 1, pto = 1 },
            WORK_CAUSES = { hydraulics = { of = 0.5 }, pto = { plf = 0.24 } },
            CARE_CAUSES = {
                careful = {},
                regular = { engine = { aicf = 0.064 }, chassis = { lubf = 0.14 } },
                neglected = { engine = { aicf = 0.419, sf = 1.5 }, transmission = { sf = 0.8 }, hydraulics = { sf = 0.6 },
                    cooling = { sf = 0.8 }, chassis = { lubf = 1.333 }, fuel = { sf = 0.5 }, pto = { sf = 0.8 } },
            },
        },
        RESALE = {
            CLASSES = {
                TRACTOR_SMALL  = { c1 = 0.981, c2 = 0.093, c3 = 0.0058, hoursPerYear = 400 },
                TRACTOR_MEDIUM = { c1 = 0.942, c2 = 0.100, c3 = 0.0008, hoursPerYear = 400 },
                TRACTOR_LARGE  = { c1 = 0.976, c2 = 0.119, c3 = 0.0019, hoursPerYear = 400 },
                COMBINE        = { c1 = 1.132, c2 = 0.165, c3 = 0.0079, hoursPerYear = 300 },
                OTHER_HARVEST  = { c1 = 0.791, c2 = 0.091, c3 = 0,      hoursPerYear = 300 },
                OTHER_VEHICLE  = { c1 = 0.786, c2 = 0.063, c3 = 0.0033, hoursPerYear = 400 },
            },
            TRACTOR_MEDIUM_POWER = 80,
            TRACTOR_LARGE_POWER = 150,
            PROFILE_CLASSES = {
                HARVESTER = "COMBINE", FORAGE_HARVESTER = "COMBINE", ROOT_HARVESTER = "COMBINE",
                SPECIALTY_HARVESTER = "COMBINE", SUGARCANE_HARVESTER = "COMBINE", MOWER = "OTHER_HARVEST",
                SPRAYER = "OTHER_VEHICLE", LOADER_COMPACT = "OTHER_VEHICLE", WHEEL_LOADER = "OTHER_VEHICLE",
                TELEHANDLER = "OTHER_VEHICLE", FORESTRY = "OTHER_VEHICLE", ROAD_LIGHT = "OTHER_VEHICLE",
                ROAD_HEAVY = "OTHER_VEHICLE",
            },
            NEW_SHARE = 0.85,
        },

        CONCURRENT_BREAKDOWN_LIMIT_PER_VEHICLE = 15,
        ENABLE_WARNING_MESSAGES = true,

        AI_WORKER = {
            -- km/h
            MIN_SPEED = 5,
            SLOW_DOWN_LEVEL = 0.5,
            RESUME_LEVEL = 0.25,
            -- km/h per second
            SLOW_DOWN_RATE = 1.0,
            RESUME_RATE = 0.5,
            RELEASE_MARGIN = 3,
            -- seconds
            OVERLOAD_SMOOTHING = 2
        },
        WORN_PART_RAMP_START = 0.34,
        WORN_PART_SYMPTOMS = {
            { effect = "ENGINE_TORQUE_MODIFIER", system = "ENGINE", amplitude = -0.30, exponent = 3, aggregation = "sum",
                combustion = { "PISTON_RINGS", "CYLINDER_LINERS", "PISTONS", "INLET_VALVES", "EXHAUST_VALVES",
                    "CYLINDER_HEAD_GASKET", "CYLINDER_HEAD", "TURBOCHARGER_MALFUNCTION" },
                electric = { "ELECTRIC_MOTOR_BEARING_WEAR", "ELECTRIC_MOTOR_WINDING_FAULT" } },
            { effect = "EXHAUST_OIL", system = "ENGINE", amplitude = 0.55, exponent = 2, aggregation = "max",
                combustion = { "PISTON_RINGS", "CYLINDER_LINERS", "PISTONS", "VALVE_GUIDES_SEALS", "TURBOCHARGER_MALFUNCTION" } },
            { effect = "FUEL_CONSUMPTION_MODIFIER", system = "FUEL", amplitude = 0.60, exponent = 3, aggregation = "sum",
                combustion = { "FUEL_INJECTOR_MALFUNCTION", "PISTON_RINGS", "CYLINDER_LINERS", "PISTONS", "INLET_VALVES", "EXHAUST_VALVES" },
                electric = { "ELECTRIC_MOTOR_BEARING_WEAR", "ELECTRIC_MOTOR_WINDING_FAULT" } },
            { effect = "ENGINE_HARD_START_MODIFIER", system = "ENGINE", amplitude = 6, exponent = 3, aggregation = "max",
                extraData = { timer = 0, status = "IDLE" },
                combustion = { "BATTERY_SULFATION", "STARTER_FAILURE", "PISTON_RINGS", "CYLINDER_LINERS", "PISTONS",
                    "INLET_VALVES", "EXHAUST_VALVES", "CYLINDER_HEAD_GASKET", "CYLINDER_HEAD" } },
            { effect = "TRANSMISSION_SLIP_EFFECT", system = "TRANSMISSION", amplitude = 0.30, exponent = 3, aggregation = "max",
                combustion = { "MANUAL_TRANSMISSION_CLUTCH_WEAR" } },
            { effect = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", system = "TRANSMISSION", amplitude = 0.30, exponent = 3,
                aggregation = "max", extraData = { timer = 0, status = "IDLE", duration = 1000, backup = 0 },
                combustion = { "TRANSMISSION_PUMP_MALFUNCTION" } },
            { effect = "CVT_MAX_RATIO_MODIFIER", system = "TRANSMISSION", amplitude = 0.30, exponent = 3, aggregation = "max",
                combustion = { "CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION" } },
            { effect = "HYDRAULIC_SPEED_MODIFIER", system = "HYDRAULICS", amplitude = -0.30, exponent = 3, aggregation = "min",
                combustion = { "HYDRAULIC_PUMP_MALFUNCTION" }, electric = { "HYDRAULIC_PUMP_MALFUNCTION" } },
            { effect = "BRAKE_FORCE_MODIFIER", system = "CHASSIS", amplitude = -0.60, exponent = 3, aggregation = "min",
                extraData = { timer = 0 },
                combustion = { "BRAKE_DISC_WEAR" }, electric = { "BRAKE_DISC_WEAR" } },
            -- degrees
            { effect = "STEERING_PLAY_EFFECT", system = "CHASSIS", amplitude = 1.5, exponent = 3, rampStart = 0.67, aggregation = "max",
                combustion = { "STEERING_LINKAGE_WEAR", "STEERING_KNUCKLE_PIVOT_WEAR", "STEERING_ORBITROL_MALFUNCTION" },
                electric = { "STEERING_LINKAGE_WEAR", "STEERING_KNUCKLE_PIVOT_WEAR", "STEERING_ORBITROL_MALFUNCTION" } },
            { effect = "RADIATOR_HEALTH_MODIFIER", system = "COOLING", amplitude = -0.20, exponent = 3, aggregation = "min",
                combustion = { "RADIATOR_CORE" }, electric = { "RADIATOR_CORE" } },
            { effect = "BATTERY_HEALTH_MODIFIER", system = "ELECTRICAL", amplitude = -0.60, exponent = 3, aggregation = "min",
                combustion = { "BATTERY_SULFATION" }, electric = { "BATTERY_SULFATION" } },
            { effect = "ALTERNATOR_HEALTH_MODIFIER", system = "ELECTRICAL", amplitude = -0.60, exponent = 3, aggregation = "min",
                combustion = { "ALTERNATOR" } },
            { effect = "ELECTRICAL_LEAKAGE_EFFECT", system = "ELECTRICAL", amplitude = 1, exponent = 3, aggregation = "sum",
                electric = { "POWER_CABLE_CONNECTION_FAILURE" } },
        },
        RENEWAL_GROUPS = {
            { "INLET_VALVES", "EXHAUST_VALVES", "VALVE_GUIDES_SEALS", "CYLINDER_HEAD_GASKET" },
            { "PISTONS", "PISTON_RINGS", "CYLINDER_LINERS", "MAIN_BEARINGS", "CONROD_BEARINGS",
                "INLET_VALVES", "EXHAUST_VALVES", "VALVE_GUIDES_SEALS", "CYLINDER_HEAD_GASKET" },
        },


        -- kW
        TURBO_MIN_POWER_KW = 56,
        -- Max rpm above which an engine burns petrol
        PETROL_ABOVE_MAX_RPM = 5500,

        BASE_BREAKDOWN_PROGRESS_TIME = 1 * 3600000,
        SECONDARY_CAUSE_SHARE = 0.35,

        -- Operating hours at part wear 1.
        MACHINE_LIFE_HOURS = 12000,
        -- Weibull shape and characteristic life (h)
        COMPONENT_LIVES = {
            BALL_BEARING           = { shape = 1.3, scale = 40000 },
            ROLLER_BEARING         = { shape = 1.3, scale = 50000 },
            PTO_OUTPUT_SHARED_BUDGET = { shape = 1.3, scale = 50000 * (2 ^ (1 / 1.3)) },
            PTO_CONTROL_SHARED_BUDGET = { shape = 1.1, scale = 75000 * (2 ^ (1 / 1.1)) },
            PTO_BRAKE_SERVICE_PROXY = { shape = 1.4, scale = 164067.071201527579 },
            BRAKE_SERVICE_BUDGET   = { shape = 1.4, scale = 164067.071201527579 },
            STEERING_COMPONENT_BUDGET = { shape = 1.4, scale = 134590.019263235619 },
            HIGH_PRESSURE_INJECTION_BUDGET = { shape = 1.1, scale = 135742.736328 },
            ADBLUE_MODULE_SERVICE_PROXY = { shape = 1.1, scale = 15000 },
            ADBLUE_DOSER_SERVICE_PROXY = { shape = 1.1, scale = 35000 },
            NOX_TRANSDUCER_PROXY = { shape = 1.0, scale = 20000 },
            DPF_FILTER_STRAINER_PROXY = { shape = 1.0, scale = 5000000 },
            TRAILER_BRAKE_VALVE    = { shape = 0.71, scale = 113460.41 },
            DRIVE_BELT             = { shape = 1.2, scale = 30000 },
            FRICTION_CLUTCH        = { shape = 1.4, scale = 100000 },
            MAGNETIC_CLUTCH        = { shape = 1.0, scale = 150000 },
            RUBBER_DIAPHRAGM       = { shape = 1.1, scale = 60000 },
            FILTER_STRAINER        = { shape = 1.0, scale = 5000000 },
            HYDRAULIC_GASKET       = { shape = 1.1, scale = 75000 },
            GEAR                   = { shape = 2.0, scale = 75000 },
            COUPLING               = { shape = 2.0, scale = 75000 },
            RELIEF_VALVE           = { shape = 1.0, scale = 100000 },
            MECHANICAL_SEAL        = { shape = 1.4, scale = 25000 },
            O_RING                 = { shape = 1.1, scale = 20000 },
            PIN                    = { shape = 1.4, scale = 50000 },
            LUBRICATOR_PUMP        = { shape = 1.1, scale = 50000 },
            CIRCUIT_BREAKER        = { shape = 1.5, scale = 100000 },
            CENTRIFUGAL_COMPRESSOR = { shape = 1.9, scale = 60000 },
            AC_MOTOR               = { shape = 1.2, scale = 100000 },
            DC_MOTOR               = { shape = 1.2, scale = 50000 },
            CENTRIFUGAL_PUMP      = { shape = 1.2, scale = 35000 },
            TRANSFORMER            = { shape = 1.1, scale = 200000 },
            SOLID_STATE_CONTROLLER = { shape = 0.7, scale = 100000 },
            CONTROL_VALVE          = { shape = 1.0, scale = 100000 },
            SOLENOID_VALVE         = { shape = 1.1, scale = 75000 },
            TRANSDUCER             = { shape = 1.0, scale = 20000 },
            ELECTRO_MECHANICAL     = { shape = 1.0, scale = 25000 },
            HALOGEN_H7             = { shape = 6.8348, scale = 550 * LAMP_LIFE_FACTOR },
            HALOGEN_H3             = { shape = 7.1912, scale = 650 * LAMP_LIFE_FACTOR },
            HALOGEN_H1             = { shape = 7.1912, scale = 650 * LAMP_LIFE_FACTOR },
            P21W                   = { shape = 5.0370, scale = 500 * LAMP_LIFE_FACTOR },
            HEAT_EXCHANGER         = { shape = 1.2, scale = 50000 },
            IMPELLER               = { shape = 2.5, scale = 150000 },
            STARTER_BATTERY        = { shape = 1.0, scale = 3700 },
            TRACTION_BATTERY       = { shape = 1.0, scale = 800000 },
            ENGINE_PISTON          = { shape = 1.4, scale = 62523.485029660369 },
            CYLINDER_LINER         = { shape = 1.8, scale = 58989.861642719734 },
            ENGINE_VALVE           = { shape = 1.4, scale = 29812.543208839306 },
            ENGINE_HEAD_GASKET     = { shape = 1.1, scale = 32018.947562309055 },
            SLEEVE_BEARING         = { shape = 1.0, scale = 69425.915774054287 },
            ENGINE_WATER_PUMP      = { shape = 1.2, scale = 12214.844949204487 },
            POWERSHIFT_REPLACEMENT_BUDGET = { shape = 1.1, scale = 176318.25099920423 },
            CVT_REPLACEMENT_BUDGET = { shape = 1.2, scale = 53453.923088420357 },
        },
        RISK_HORIZON_WEAR = 0.1,
        RISK_RATIO_MODERATE = 1.5,
        RISK_RATIO_HIGH = 2.0,
        WORN_PART_FAILED_SHARE = 0.1,
    },

    -- workshop opening hours and availability
    WORKSHOP = {
        DEALER_ALWAYS_AVAILABLE = false,
        MOBILE_ALWAYS_AVAILABLE = true,
        OWN_ALWAYS_AVAILABLE = true,
        OPEN_HOUR = 8,  
        CLOSE_HOUR = 19, 
        PRICE_MULTIPLIERS = {
            DEALER = 1.0,
            MOBILE = 1.2,
            OWN    = 0.8,
        },

        MOBILE_WORKSHOP_RESTRICTIONS_ENABLED = true,

    },
    -- service prices, durations and restore ratios
    MAINTENANCE = {
        INSTANT_INSPECTION = false,
        INSTANT_MAINTENANCE_REPAIR = false,
        INSTANT_BODYWORK = false,
        INSTANT_OVERHAUL = false,

        REFILL_TIME = 0.25 * 3600000,
        INSPECTION_TIME = 1 * 3600000,
        INSPECTION_TIME_MULTIPLIERS = {
            STANDARD = 1.0,
            VISUAL   = 0.1,
            COMPLETE = 4.0,
        },
        REPAIR_TIME_MULTIPLIERS = {
            LOW    = 0.2,
            MEDIUM = 1.0,
            HIGH   = 2.0,
        },
        REPAIR_OPERATIONS = {
            ECU_MALFUNCTION = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            POWER_CABLE_CONNECTION_FAILURE = {hours = 2, category = "diagnostic"},
            BATTERY_SULFATION = {hours = 0.5, category = "external"},
            GLOW_PLUG_FAILURE = {hours = 1.5, category = "mechanical"},
            STARTER_RELAY_FAILURE = {hours = 0.7, category = "external"},
            PREHEAT_RELAY_FAILURE = {hours = 1.5, category = "mechanical"},
            LOW_BEAM_FAILURE = {hours = 0.8, category = "external"},
            HIGH_BEAM_FAILURE = {hours = 0.8, category = "external"},
            FRONT_WORK_LIGHTS_FAILURE = {hours = 0.5, category = "external"},
            REAR_WORK_LIGHTS_FAILURE = {hours = 0.5, category = "external"},
            BEACON_LIGHTS_FAILURE = {hours = 0.5, category = "external"},
            TURN_LIGHTS_FAILURE = {hours = 0.5, category = "external"},
            ALTERNATOR = { hours = 1.4, category = "mechanical" },
            STARTER_FAILURE = {hours = 2.1, category = "mechanical"},
            INVERTER_MALFUNCTION = {hours = 4, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            DCDC_CONVERTER_FAILURE = {hours = 3, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            ONBOARD_CHARGER_FAILURE = {hours = 3, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            HV_INSULATION_LOSS = {hours = 4, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            ENGINE_JAM = {hours = 40, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            TURBOCHARGER_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            OIL_PUMP_MALFUNCTION = {hours = 8, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PISTONS = { hours = 40, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            PISTON_RINGS = { hours = 40, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            CYLINDER_LINERS = { hours = 40, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            INLET_VALVES = { hours = 12, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            EXHAUST_VALVES = { hours = 12, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            VALVE_GUIDES_SEALS = { hours = 12, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            CYLINDER_HEAD = { hours = 12, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            CYLINDER_HEAD_GASKET = { hours = 12, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            MAIN_BEARINGS = { hours = 40, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            CONROD_BEARINGS = { hours = 40, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            ELECTRIC_MOTOR_BEARING_WEAR = {hours = 8, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            ELECTRIC_MOTOR_WINDING_FAULT = {hours = 12, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            MOTOR_POSITION_SENSOR_FAULT = {hours = 3, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            MANUAL_TRANSMISSION_CLUTCH_WEAR = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = {hours = 18, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            TRANSMISSION_PUMP_MALFUNCTION = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            HYDROSTATIC_UNIT_MALFUNCTION = {hours = 24, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = {hours = 6, category = "transmission", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            TRANSMISSION_OIL_COOLER_MALFUNCTION = {hours = 2, category = "mechanical"},
            TRANSMISSION_OIL_LEAK = {hours = 10, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            CVT_ADDON_MALFUNCTION = {hours = 8, category = "transmission", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            REDUCER_GEAR_WEAR = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            HYDRAULIC_PUMP_MALFUNCTION = {hours = 6, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            HYDRAULIC_CYLINDER_INTERNAL_LEAK = {hours = 4, category = "mechanical"},
            HYDRAULIC_HOSE_EXTERNAL_LEAK = {hours = 1, category = "external"},
            HYDRAULIC_FILTER_CLOGGING = {hours = 0.75, category = "external"},
            TRANSMISSION_FILTER_CLOGGING = {hours = 0.75, category = "external"},
            HYDRAULIC_OIL_COOLER_MALFUNCTION = {hours = 3, category = "mechanical"},
            HYDRAULIC_SPOOL_VALVE_MALFUNCTION = {hours = 5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PTO_CLUTCH_WEAR = {hours = 10, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PTO_OUTPUT_BEARING_WEAR = {hours = 8, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PTO_OUTPUT_SEAL_LEAK = {hours = 4, category = "mechanical"},
            PTO_ENGAGEMENT_SOLENOID_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            PTO_OUTPUT_SHAFT_FAILURE = {hours = 8, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PTO_ENGAGEMENT_SWITCH_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            PTO_SPEED_SENSOR_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            PTO_BRAKE_FAILURE = {hours = 6, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FRONT_PTO_CLUTCH_FAILURE = {hours = 10, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            BRAKE_DISC_WEAR = {hours = 6, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            BRAKE_CONTROL_FAILURE = {hours = 6, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            TRAILER_BRAKE_VALVE_FAILURE = {hours = 5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PARK_BRAKE_MALFUNCTION = {hours = 6, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            WHEEL_HUB_BEARING_WEAR = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            STEERING_LINKAGE_WEAR = {hours = 2, category = "external"},
            STEERING_KNUCKLE_PIVOT_WEAR = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            STEERING_ORBITROL_MALFUNCTION = {hours = 5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            STEERING_CYLINDER_LEAK = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            LOADER_PIVOT_PIN_WEAR = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            CAB_SUSPENSION_DAMPER_LEAK = {hours = 4, category = "mechanical"},
            TRACK_ROLLER_BEARING_WEAR = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            TRACK_TENSIONER_MALFUNCTION = {hours = 5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            THERMOSTAT_MALFUNCTION = {hours = 2, category = "mechanical"},
            COOLANT_HOSE_FAILURE = {hours = 0.9, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            EXPANSION_TANK_FAILURE = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            ACCESSORY_BELT_FAILURE = {hours = 1.2, category = "mechanical"},
            FAN_BLADE_FAILURE = {hours = 3, category = "mechanical"},
            ELECTRIC_COOLING_FAN_FAILURE = {hours = 3, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FAN_CLUTCH_FAILURE = {hours = 3, category = "mechanical"},
            COOLANT_PUMP_FAILURE = {hours = 3, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            THERMAL_WATER_PUMP = { hours = 3, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            RADIATOR_CORE = { hours = 6.5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK" },
            FUEL_PUMP_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FUEL_INJECTOR_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            HIGH_PRESSURE_PUMP_MALFUNCTION = {hours = 3.5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FUEL_FILTER_CLOGGING = {hours = 0.75, category = "external"},
            ADBLUE_FILTER_CLOGGING = {hours = 0.75, category = "external"},
            FUEL_LINE_AIR_LEAK = {hours = 1.5, category = "external"},
            MECHANICAL_INJECTION_PUMP_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FUEL_METERING_VALVE_FAILURE = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            RAIL_PRESSURE_SENSOR_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            RAIL_PRESSURE_LIMITER_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            GAS_PRESSURE_REGULATOR_FAILURE = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            GAS_SHUTOFF_SOLENOID_FAILURE = {hours = 0.5, category = "external"},
            GAS_FILTER_CLOGGING = {hours = 0.75, category = "external"},
            GAS_LINE_LEAK = {hours = 1.5, category = "external"},
            GAS_INJECTOR_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            ADBLUE_PUMP_FAILURE = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            ADBLUE_DOSER_FAILURE = {hours = 1.6, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            NOX_SENSOR_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            PARTICULATE_FILTER_FAILURE = {hours = 8, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PARTICULATE_FILTER_SOOT_OVERLOAD = {hours = 1, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            TRACTION_BATTERY_CELL_FAULT = {hours = 12, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            HV_CONTACTOR_FAILURE = {hours = 4, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            GEARBOX_BEARING_FAILURE = {hours = 18, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            POWERSHIFT_CLUTCH_FAILURE = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            POWERSHIFT_REVERSER_FAILURE = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            TRANSMISSION_CONTROL_FAILURE = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            TRANSMISSION_SENSOR_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            CVT_SENSOR_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            FRONT_AXLE_SHAFT_WEAR = {hours = 2, category = "external"},
            AXLE_BEARING_WEAR = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            REAR_BEVEL_GEAR_FAILURE = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FINAL_DRIVE_FAILURE = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            DIFFERENTIAL_FAILURE = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            DIFF_LOCK_CONTROL_FAILURE = {hours = 6, category = "transmission", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            FOUR_WD_CONTROL_FAILURE = {hours = 6, category = "transmission", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            LIFT_VALVE_FAILURE = {hours = 5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            LIFT_POSITION_SENSOR_FAILURE = {hours = 4, category = "mechanical"},
            LOADER_CONTROL_FAILURE = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            HYDRAULIC_QUICK_COUPLER_FAILURE = {hours = 1, category = "external"},
        },
        OVERHAUL_TIME = 24 * 3600000,
        OVERHAUL_TIME_MULTIPLIERS = {
            STANDARD = 1.0,
            PARTIAL  = 1.2,
            FULL     = 2.0,
        },

        REPAINT_TIME = 8 * 3600000,

        INSPECTION_DETECTION_CHANCE_MULTIPLIERS = {
            STANDARD = 1.0,
            VISUAL   = 0.8,
            COMPLETE = 1.0,
        },
        INSPECTION_TOOL_CATEGORIES = { diagnostic = true, highVoltage = true },

        OVERHAUL_CONDITION_TARGETS = {
            STANDARD = 0.75,
            PARTIAL  = 0.75,
            FULL     = 1.0,
        },

        PARTS_BREAKDOWN_CHANCES = {
            OEM         = 0.0,
            USED        = 0.06,
            AFTERMARKET = 0.03,
        },

        USED_PART_DONOR_HOURS = {
            2000, 2192, 2200, 4422, 6120, 6273, 6483, 6494, 6766, 6956, 8000, 8025, 8200, 10156, 10477, 11700, 12480
        },

        PARTS_PRICE_MULTIPLIERS = {
            OEM         = 1.0,
            USED        = 0.33,
            AFTERMARKET = 0.66,
        },
        REFERENCE_POWER = 160,
        -- EUR per hour
        LABOUR_RATE = 90,
        LABOUR_POWER_EXPONENT = 0.4,
        PARTS_POWER_EXPONENT = 0.6,
        PROFILE_PRICE_FACTORS = {
            ROAD_LIGHT = { labour = 0.3,  filters = 0.2, parts = 0.5  },
            ROAD_HEAVY = { labour = 0.55, filters = 0.2, parts = 0.75 },
        },
        MAINTENANCE_LABOUR_HOURS = {
            STANDARD   = 2.5,
            EXTENDED   = 5.0,
            PREVENTIVE = 8.0,
        },
        MAINTENANCE_FILTER_PRICES = {
            STANDARD   = 350,
            EXTENDED   = 550,
            PREVENTIVE = 700,
        },
        REPAIR_REFERENCE_VALUE = 163100,
        OVERHAUL_REFERENCE_VALUE = 32500,

        REPAIR_PRICE_MULTIPLIERS = {
            LOW    = 0.2,
            MEDIUM = 1.0,
            HIGH   = 2.0,
        },
        OVERHAUL_PRICE_MULTIPLIERS = {
            STANDARD = 0.5,
            PARTIAL  = 0.6,
            FULL     = 0.8,
        },
        OVERHAUL_MAX_PRICE_RATIO = 1.0,
    },
    -- Heating: C/s; cooling: 1/s.
    THERMAL = {
        TAU = 5000,
        PID_TARGET_TEMP = 90,
        TELLTALE = { WARNING = 99, CRITICAL = 110 },
        ENGINE_PROTECTION = {
            START_TEMP = 110,
            SEVERE_TEMP = 115,
            RELEASE_TEMP = 107,
            SEVERE_RELEASE_TEMP = 112,
        },
        FAN_AIRFLOW_EXPONENT = 0.39,
        FAN_DRIVE_YEARS = { VISCOUS = 1997, ELECTRONIC = 2013 },
        REVERSIBLE_FAN = { KIT_PRICE = 2176, REVERSAL_MS = 15000, AUTO_INTERVAL_MS = 1200000, MIN_YEAR = 2007, AUTO_MIN_YEAR = 2008 },
        PROFILES = {
            diesel = {
                warmup = {
                    power = { 0.0694, 1 / 3, 2 / 3, 1 },
                    climates = {
                        { ambient = 0, cooling = 0.00159200378482027,
                            heat = { 0.126440431514204, 0.193839492462645, 0.207207189634561, 0.280168086068943 } },
                        { ambient = 10, cooling = 0.00178584873723889,
                            heat = { 0.124437828513334, 0.183692665311297, 0.197328232968797, 0.256371523588326 } },
                        { ambient = 20, cooling = 0.0022334592320928,
                            heat = { 0.136166071790457, 0.186364516906941, 0.19606598642592, 0.265217056918726 } },
                    },
                },
                activeResponseRate = 1.15,
                heatIdle = 0.0025000000000000001,
                heatLoad = 0.12633658888290838,
                heatRpm = 0.001,
                heatDrive = 0,
                heatExternal = 0,
                heatHydraulic = 0,
                heatChargeCapacityShare = 0,
                passiveCooling = 0.00035,
                speedCooling = 0.00014999999999999999,
                forcedCooling = 0.0027000000000000001,
                regulatedMin = 82,
                regulatedMax = 97,
                faultHeatScale = 0.12365389417419846,
            },
            evDrive = {
                heatIdle = 0,
                heatLoad = 0.027,
                heatRpm = 0.002,
                heatDrive = 0,
                heatExternal = 0,
                heatHydraulic = 0,
                heatChargeCapacityShare = 0,
                passiveCooling = 0.00038508176697774738,
                speedCooling = 0.0001,
                forcedCooling = 0.0011999999999999999,
                regulatedMin = 50,
                regulatedMax = 65,
                faultHeatScale = 0.064444444444444443,
            },
            separateTrans = {
                activeResponseRate = 1.30,
                heatIdle = 0.0030000000000000001,
                heatLoad = 0,
                heatRpm = 0.002,
                heatDrive = 0.022371747050598544,
                heatExternal = 0.0040000000000000001,
                heatHydraulic = 0,
                heatChargeCapacityShare = 0,
                passiveCooling = 0.00012836058899258246,
                speedCooling = 5.0000000000000002e-05,
                forcedCooling = 0.001,
                regulatedMin = 45,
                regulatedMax = 70,
                faultHeatScale = 0.029877854333903376,
            },
            commonOil = {
                activeResponseRate = 1.30,
                heatIdle = 0.0030000000000000001,
                heatLoad = 0,
                heatRpm = 0.002,
                heatDrive = 0.022371747050598544,
                heatExternal = 0.0040000000000000001,
                heatHydraulic = 0.012,
                heatChargeCapacityShare = 0,
                passiveCooling = 0.00012836058899258246,
                speedCooling = 5.0000000000000002e-05,
                forcedCooling = 0.001,
                regulatedMin = 45,
                regulatedMax = 70,
                faultHeatScale = 0.029877854333903376,
            },
            hydraulic = {
                activeResponseRate = 1.30,
                heatIdle = 0.002,
                heatLoad = 0,
                heatRpm = 0.002,
                heatDrive = 0,
                heatExternal = 0,
                heatHydraulic = 0.025000000000000001,
                heatChargeCapacityShare = 0,
                passiveCooling = 0.00012836058899258246,
                speedCooling = 5.0000000000000002e-05,
                forcedCooling = 0.001,
                regulatedMin = 45,
                regulatedMax = 70,
                faultHeatScale = 0.19333333333333336,
            },
            battery = {
                heatIdle = 0,
                heatLoad = 0.0013888888888888889,
                heatRpm = 0.00027777777777777778,
                heatDrive = 0,
                heatExternal = 0,
                heatHydraulic = 0,
                heatChargeCapacityShare = 14.184023258336397,
                passiveCooling = 4.6296296296296294e-05,
                speedCooling = 5.0000000000000004e-06,
                forcedCooling = 0,
                regulatedMin = 0,
                regulatedMax = 1,
                faultHeatScale = 0,
            },
        }
    },

    FIELD_CARE = {
        CLEANING_SPEED = 0.05,
        AIR_FILTER_BREAKDOWN_THRESHOLD = 0.5,
        AIR_FILTER_BLOWOUT_RESIDUE_SHARE = 0.25,
        AIR_FILTER_REPLACEMENT_RESIDUE = 0.35,
        FILTER_STAGE_THRESHOLDS = { 1.0, 4 / 3, 5 / 3, 2.0 },
        FUEL_FILTER_LOW_FUEL_MULTIPLIER = 3.0,
        HYDRAULIC_FILTER_ACTIVE_MULTIPLIER = 2.0,
        ADBLUE_FILTER_SERVICE_INTERVALS = 6,
        VISUAL_INSPECTION_DURATION = 5000,
        LUBRICATION_REDUCE_PER_OPERATING_HOUR = 0.05,
        LUBRICATION_RESTORE_PER_USE = 0.1,
        LUBRICATION_DRY_THRESHOLD = 0.60,
        LUBRICATION_VERY_DRY_THRESHOLD = 0.35,
        LUBRICATION_CRITICALLY_DRY_THRESHOLD = 0.15,
        LUBRICATION_WARNING_THRESHOLD = 0.80,
        LUBRICATION_REDUCE_PER_PERIOD = 0.1,
        RAYCAST_DISTANCE = 5.0,
        JUMPER_CABLES_MAX_CONNECTION_DISTANCE = 12.0,
    },

    -- Fluid levels
    FLUIDS = {
        -- Exact vehicle XML keys override category profiles.
        CAPACITY_OVERRIDES = {},

        ENGINE_OIL_CONSUMPTION_PER_INTERVAL = 0.15 / 1.45,
        ENGINE_OIL_WEAR_CONSUMPTION = 13.5,
        ENGINE_OIL_LOAD_SHARE = 1.5,

        LEVEL_MIN_MARK = 0.85,
        LEVEL_LOW = 0.70,
        LEVEL_VERY_LOW = 0.50,
        LEVEL_CRITICALLY_LOW = 0.30,
        LOW_LEVEL_WEAR_MULTIPLIER = 4.0,
    },

    -- drive mode, differential lock and park brake
    DRIVETRAIN = {
        ENABLED = true,
        ALLOW_AUTO_MODE = true,

        OPEN_AXLE_SPEED_RATIO = 4.0,
        LOCKED_AXLE_SPEED_RATIO = 1.0,

        AUTO_ENGAGE_SLIP_THRESHOLD = 0.12,
        AUTO_ENGAGE_LOAD_THRESHOLD = 0.55,
        AUTO_ENGAGE_SPEED = 13,
        AUTO_DISENGAGE_SPEED = 20,
        AUTO_HYSTERESIS_MS = 250,

        WINDUP_STEER_THRESHOLD = 0.12,
        WINDUP_FRICTION_THRESHOLD = 0.85,
        WINDUP_4WD_FACTOR = 0.15,
        WINDUP_4WD_MAX_STRESS = 0.18,
        WINDUP_ACCUMULATION_RATE = 0.09,
        WINDUP_RELEASE_RATE = 0.25,
        WINDUP_WEAR_MULTIPLIER = 12.0,
        WINDUP_INSTANT_DAMAGE = 0.03,
        WINDUP_TUTORIAL_THRESHOLD = 0.05,
        WINDUP_4WD_WARNING_THRESHOLD = 0.05,
        WINDUP_WARNING_THRESHOLD = 0.22,
        WINDUP_CRITICAL_THRESHOLD = 0.44,

        EXCLUDED_CATEGORIES = {
            CARS = true,
            TRUCKS = true
        },
        MACHINE_CATEGORIES = {
            FRONTLOADERVEHICLES = true,
            TELELOADERVEHICLES = true,
            WHEELLOADERVEHICLES = true,
            SKIDSTEERVEHICLES = true,
            FORKLIFTS = true,
            FORESTRYHARVESTERS = true,
            FORESTRYFORWARDERS = true,
            FORESTRYEXCAVATORS = true
        },

        PARKBRAKE_ENABLED = true,
        PARKBRAKE_AUTO_MIN_YEAR = 2010,
        PARKBRAKE_AUTO_STANDSTILL_MS = 45000,
        PARKBRAKE_LEVER_HOLD = 0.5,
        PARKBRAKE_AIR_HOLD = 1.0,
        PARKBRAKE_ROLLING_RESISTANCE = 0.03, 
        PARKBRAKE_DRAG_WEAR_MULTIPLIER = 5.0 
    },

    -- Exhaust
    EXHAUST = {
        ENABLED = true,

        -- Soot, oil, unburnt fuel, water vapour, clean gas.
        SOOT_TINT = {0.020, 0.020, 0.025},
        OIL_TINT = {0.050, 0.090, 0.350},
        UNBURNT_TINT = {0.980, 0.980, 0.980},
        VAPOUR_TINT = {0.920, 0.930, 0.950},
        CLEAN_TINT = {0.780, 0.780, 0.780},

        K_SOOT = 1.50,
        K_OIL = 1.20,
        K_UNBURNT = 1.00,
        OPACITY_FLOOR = 0.03,

        DEF_SOOT_FACTOR = 0.20,
        METHANE_SOOT_FACTOR = 0.10,
        AFTERTREATMENT_FAULT_FLOOR = 0.35,

        FLOW_BOOST_GAIN = 0.60,

        PLUME_EMIT_SHAPE = "particles/exhaust/plumeEmitShape.i3d",
        PLUME_SPRITES = "soft",
        PLUME_DIRECTORY = "particles/exhaust/",
        PLUME_FILE = "plume.i3d",

        PUFF = {
            OVERLAP_TARGET = 5,
            RATE_MIN = 8,
            RATE_MAX = 720,
            THIN_LEVEL_MAX = 6,
            -- Exit speed (m/s)
            EXIT_SPEED_MIN = 2.0,
            EXIT_SPEED_FULL = 30.0,
            SPREAD_SHARE = 0.02,
            -- Tailpipe diameter per square root of kW (m)
            PIPE_DIAMETER_PER_SQRT_KW = 0.009,
            PIPE_DIAMETER_MIN = 0.06,
            PIPE_DIAMETER_MAX = 0.16,
            SPRITE_GAS_RATIO = 1.65,
            RADIUS_SHARE = 0.45,
            SIZE_MAX = 8.0,
            JET_SPREAD = 0.22,
            JET_CROSS_SPREAD = 0.10,
            -- Jet integration step (ms)
            JET_PROFILE_STEP_MS = 50,
            GROWTH_BASE = 0.18,
            GROWTH_PER_WIND = 0.15,
            -- Sprite growth interval (ms)
            GROWTH_FIT_SHARE = 0.35,
            GROWTH_FIT_MIN_MS = 400,
            GROWTH_FIT_LEVEL_MIN_MS = 20,
            GROWTH_FIT_MAX_MS = 4000,
            RISE_SPEED = 0.40,
            REFERENCE_SIZE = 0.50,
            LIFE_MIN = 800,
            LIFE_MAX = 8000,
            TAU_VISIBLE = 0.02,
            SPRITE_ALPHA_GAIN = 1.60,
            ALPHA_EPSILON = 0.03,
            FADE_OUT_MS = 300,
            -- Air drag (1/s)
            BASE_DAMPING = 1.20,
            DAMPING_CROSS_SPEED = 2.0,
            DAMPING_FLOOR_SHARE = 0.30,
            SURFACE_SPREAD = 0.06,
            SURFACE_FLOW_SHARE = 0.85,
            SURFACE_PUSH_SPEED = 1.5,
            -- Roof probe radius threshold (m)
            ROOF_PROBE_MIN_RADIUS = 0.30,
            SHELTER_WIND_SHARE = 0.15,
            SHELTER_RADIUS = 8.0,
            SHELTER_CHECK_MS = 200,
            SHELTER_TAU = 400,
            LEE_SEARCH_DISTANCE = 40,
            LEE_PROBE_HEIGHT = 30,
            LEE_MIN_WIND = 0.5,
            LEE_WIND_SHARE = 0.25,
            LEE_FULL_HEIGHTS = 2,
            LEE_RECOVERY_HEIGHTS = 10,
            LEE_TOP_BLEND = 1.5,
            LEE_GROUND_FALLBACK = 2.5,
            -- Ray origin tolerance (m)
            INSIDE_HIT_DISTANCE = 0.001,
            POOL_MAX = 400
        },

        EGT = {
            RISE_IDLE_K = 120,
            RISE_FULL_K = 430,
            COLD_FACTOR = 0.45,
            DILUTION_EXPONENT = 1.30
        },

        TURBULENCE = {
            BASE = 0.35,
            PER_WIND = 0.30,
            VERTICAL_SHARE = 0.60,
            OCTAVES = {
                {wavelength = 4.0, frequency = 0.35, weight = 1.00},
                {wavelength = 1.7, frequency = 0.70, weight = 0.55},
                {wavelength = 0.7, frequency = 1.40, weight = 0.30}
            }
        },

        VAPOUR = {
            START_C = 8,
            FULL_C = -10,
            K = 1.10,
            HUMIDITY_BASE = 0.60,
            HUMIDITY_WEATHER = 0.40,
            IDLE_SHARE = 0.55,
            COLD_ENGINE_BOOST = 0.40,
            EVAPORATION_WARM_MS = 300,
            EVAPORATION_COLD_MS = 1400
        },

        BURST_DECAY_TAU = 350,
        BURST_EMIT_GAIN = 0.50,
        BURST_SPEED_GAIN = 0.50,
        BURST_TAU_GAIN = 0.50,
        BURST_REFRACTORY = 2000,
        BURST_SLOW_TAU = 250,
        BURST_LATCH_RESET = 0.50,
        BURST_EDGE = {
            BOOST_DEFICIT = 0.30,
            UNBURNT = 0.08,
            WET_STACKING = 0.06,
            PREHEAT = 0.20,
            FAULT = 0.10
        },

        TUNE_INTERVAL = 80,

        -- Culling distance (m)
        PLUME_CLIP_DISTANCE = 150,

        -- Smoothing time constants (ms)
        TINT_TAU = 900,
        RISE_TAU = 250,
        SOOT_RISE_TAU = 150,

        SOOT_FALL_TAU = 350,
        BURST_RISE_TAU = 40,
        FALL_TAU = 1200,
        VAPOUR_TAU = 1500,

        ERA_BREAKDOWN_FLOOR = 0.60,

        ERA_FACTORS = {
            {2001, 1.00},
            {2006, 0.70},
            {2011, 0.40},
            {2014, 0.25},
            {9999, 0.18}
        },

        UNBURNT_ERA_FACTORS = {
            {2001, 1.00},
            {2006, 0.90},
            {2011, 0.80},
            {2014, 0.70},
            {9999, 0.60}
        },

        STAGE_V = {
            OUTER_POWER_YEAR = 2019,
            MID_POWER_YEAR = 2020,
            MIN_POWER_KW = 19,
            MID_POWER_MIN_KW = 56,
            MID_POWER_MAX_KW = 130,
            SOOT_FACTOR = 0.15
        },
        PARTICULATE_FILTER = {
            FILL_HOURS = 28,
            PASSIVE_LOAD = 0.40,
            REGENERATION_MS = 1500000,
            REGENERATION_COOLANT = 70,
            DERATE_LEVEL = 1.14,
            SERVICE_LEVEL = 1.44,
            DERATE_RPM = 1500
        },
        SCR_INDUCEMENT = {
            DOSING = { LOW_HOURS = 10, SEVERE_HOURS = 20 },
            MONITORING = { LOW_HOURS = 36, SEVERE_HOURS = 100 },
            LOW_TORQUE = 0.75,
            SEVERE_TORQUE = 0.5,
            SEVERE_RPM = 0.6,
            TORQUE_STEP_PER_MINUTE = 0.01
        },
        SOOT = {
            FUEL_IDLE_SHARE = 0.25,
            LOAD_THRESHOLD = 0.80,
            LOAD_FULL = 1.05,
            LOAD_MAX = 0.35,
            WET_STACKING_MAX = 0.35,
            BOOST_DEFICIT_THRESHOLD = 0.45,
            BOOST_DEFICIT_FULL = 0.75,
            TRANSIENT_MAX = 0.50,
            AIR_FILTER_KNEE = 0.50,
            AIR_FILTER_MAX = 0.30,
            SERVICE_THRESHOLD = 0.50,
            SERVICE_MAX = 0.10,
            BREAKDOWN_MAX = 1.00
        },

        OIL = {
            IDLE_LOAD_THRESHOLD = 0.30,
            IDLE_BOOST = 1.60,
            BREAKDOWN_MAX = 1.00
        },

        UNBURNT = {
            COLD_THRESHOLD_C = 50,
            COLD_FULL_C = -10,
            COLD_MAX = 0.50,
            CRANKING_BOOST = 2.00,
            PREHEAT_FAULT_MAX = 0.40,
            BREAKDOWN_MAX = 1.00
        }
    },

    PREHEAT = {
        LAMP_TEST_DURATION_MS = 1000,
        MAX_AUTOMATIC_CRANK_MS = 10000,
        START_ASSIST_TEMPERATURE_C = 5,
        ACTIVATION_TEMPERATURE_C = 25,
        WAIT_TIME_CURVE = {
            {-15, 15000},
            {-10, 10000},
            {-5, 5000},
            {0, 4000},
            {5, 2500},
            {20, 2500},
            {25, 0}
        }
    },

    -- Electrical
    ELECTRICAL = {
        RATING = {
            POWER_RANGE_HP = { 20, 705 },
            YEAR_RANGE = { 1970, 2026 },
            ALTERNATOR_A = { base = 80.7, powerExponent = 0.53, decadeFactor = 1.27 },
            BATTERY_AH = { base = 124.6, powerExponent = 0.60, decadeFactor = 0.93 },
            STARTER_KW = { base = 2.93, powerExponent = 0.44, decadeFactor = 1 },
            ALTERNATOR_STEP_A = 5,
            BATTERY_STEP_AH = 10,
            TELEHANDLER_ALTERNATOR_A = 90,
            SYSTEM_24V_FAMILIES = { FORESTRY = true, ROAD_HEAVY = true },
            WHEEL_LOADER_24V_ABOVE_HP = 110,
            BATTERY_24V_AH = 180,
            ROAD_LIGHT = { alternatorA = 175, batteryCapacityAh = 156, starterKw = 4.2 }
        },
        -- Voltages refer to one 12 V battery.
        OCV_CURVE = { { 0, 11.7 }, { 0.25, 12.0 }, { 0.5, 12.2 }, { 0.75, 12.4 }, { 1, 12.6 } },
        REGULATED_VOLTAGE_V = 14.0,
        MIN_CRANKING_VOLTAGE_V = 7.2,
        -- One-amp-hour battery resistance (ohms)
        INTERNAL_RESISTANCE_CURVE = { { -18, 0.51 }, { -10, 0.49 }, { 0, 0.46 }, { 25, 0.30 } },
        EMPTY_RESISTANCE_FACTOR = 2.0,
        CRANKING_DRAG_CURVE = { { -19, 0.65 }, { 22, 1 } },
        FIRING_CRANKING_SPEED = 0.4,
        INACCESSIBLE_CHARGE_CURVE = { { -18, 0.54 }, { -12, 0.44 }, { -7, 0.34 }, { -1, 0.27 }, { 2, 0.21 }, { 10, 0.12 }, { 27, 0 } },
        CHARGE_ACCEPTANCE_BULK = 1.5,
        CHARGE_ACCEPTANCE_TOPPING = 0.04,
        CHARGE_TOPPING_SOC = 0.80,
        ALTERNATOR_IDLE_FACTOR = 2 / 3,
        BASE_LOAD_ECU_A = 15,
        BASE_LOAD_A = 8,
        CAB_FAN_A = 14,
        AIR_CONDITIONING_A = 4,
        AIR_CONDITIONING_MIN_TEMP_C = 20,
        ROAD_LIGHTS_A = 9,
        LAMP_VOLTAGE_V = 12,
        WORK_LAMPS_BEFORE_1990 = 2,
        WORK_LAMPS_BEFORE_2012 = 6,
        WORK_LAMPS_BY_POWER = { { 100, 4 }, { 170, 6 }, { 300, 8 }, { 400, 10 }, { math.huge, 12 } },
        WORK_LAMPS_HARVESTER_FACTOR = 2,
        WORK_LAMP_HALOGEN_W = 55,
        WORK_LAMP_LED_W = 45,
        -- year LEDs are offered on most machines, by light circuit
        LED_YEARS = { LOW_BEAM_FAILURE = 2017, HIGH_BEAM_FAILURE = 2017, FRONT_WORK_LIGHTS_FAILURE = 2015,
            REAR_WORK_LIGHTS_FAILURE = 2015, BEACON_LIGHTS_FAILURE = 2017, TURN_LIGHTS_FAILURE = 2016 },
        -- Starter current per kW (A)
        STARTER_CURRENT_CURVE = { { -20, 165 }, { 0, 145 } },
        GLOW_PLUG_A = 12,
        GLOW_PLUGS_BY_POWER = { { 130, 4 }, { math.huge, 6 } },
        STANDBY_A = 0.05,
        LEAKAGE_FAULT_A = 0.1,
        SELF_DISCHARGE_PER_MONTH = 0.05,
        SELF_DISCHARGE_REFERENCE_TEMP_C = 25,
        SELF_DISCHARGE_DOUBLING_C = 10,
        MONTH_HOURS = 730.5,
        CIRCUIT_ADMISSIBLE_DROP_V = 0.7,
        JUMPER_CABLE_RESISTANCE_OHM = 0.00625,
        VOLTAGE_SAG_V = 12.0,
        VOLTAGE_SAG_DELAY_MS = 2000,
        SYSTEM_VOLTAGE_TAU_MS = 250
    },

    -- Diagnostic tool
    DIAGNOSTIC = {
        LICENCE_PRICE = 595,
        SCAN_DURATION_MS = 120000,
        -- Controller scan order
        ECUS = { "ENGINE", "INVERTER", "TRACTION_BATTERY", "CONVERTER", "CHARGER", "TRANSMISSION", "TRACTOR", "DASHBOARD" },
        FAULT_CODES = {
            ECU_MALFUNCTION = { ecu = "ENGINE", spn = 523612, warning = 12, critical = 12 },
            TURBOCHARGER_MALFUNCTION = { ecu = "ENGINE", spn = 102, warning = 1, critical = 1 },
            OIL_PUMP_MALFUNCTION = { ecu = "ENGINE", spn = 100, warning = 1, critical = 1 },
            PISTONS = { ecu = "ENGINE", spn = 101, warning = 16, critical = 16 },
            PISTON_RINGS = { ecu = "ENGINE", spn = 101, warning = 16, critical = 16 },
            CYLINDER_LINERS = { ecu = "ENGINE", spn = 101, warning = 16, critical = 16, branches = { [2] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 } } },
            INLET_VALVES = { ecu = "ENGINE", spn = 1323, warning = 12, critical = 12, cylinders = 3 },
            EXHAUST_VALVES = { ecu = "ENGINE", spn = 1323, warning = 12, critical = 12, cylinders = 3 },
            CYLINDER_HEAD = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0,
                branches = { [2] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 }, [3] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 } } },
            CYLINDER_HEAD_GASKET = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0,
                branches = { [2] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 }, [3] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 } } },
            MAIN_BEARINGS = { ecu = "ENGINE", spn = 100, warning = 1, critical = 1 },
            CONROD_BEARINGS = { ecu = "ENGINE", spn = 100, warning = 1, critical = 1 },
            FUEL_INJECTOR_MALFUNCTION = { ecu = "ENGINE", spn = 1323, cylinders = 3, warning = 12, critical = 12 },
            HIGH_PRESSURE_PUMP_MALFUNCTION = { ecu = "ENGINE", spn = 157, warning = 18, critical = 1 },
            FUEL_PUMP_MALFUNCTION = { ecu = "ENGINE", spn = 94, warning = 1, critical = 1 },
            FUEL_METERING_VALVE_FAILURE = { ecu = "ENGINE", spn = 157, warning = 18, critical = 1 },
            RAIL_PRESSURE_SENSOR_FAILURE = { ecu = "ENGINE", spn = 157, warning = 3, critical = 4 },
            RAIL_PRESSURE_LIMITER_FAILURE = { ecu = "ENGINE", spn = 157, warning = 18, critical = 1 },
            ADBLUE_PUMP_FAILURE = { ecu = "ENGINE", spn = 4375, warning = 5, critical = 4 },
            ADBLUE_DOSER_FAILURE = { ecu = "ENGINE", spn = 3361, warning = 3, critical = 4 },
            NOX_SENSOR_FAILURE = { ecu = "ENGINE", spn = 3216, warning = 2, critical = 4 },
            PARTICULATE_FILTER_FAILURE = { branches = {
                [1] = { ecu = "ENGINE", spn = 3251, warning = 1, critical = 1 },
                [2] = { ecu = "ENGINE", spn = 3251, warning = 0, critical = 0 } } },
            PARTICULATE_FILTER_SOOT_OVERLOAD = { ecu = "ENGINE", spn = 524135, warning = 14, critical = 0 },
            THERMOSTAT_MALFUNCTION = { branches = { [2] = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0 } } },
            COOLANT_PUMP_FAILURE = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0 },
            THERMAL_WATER_PUMP = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0, branches = { [2] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 } } },
            RADIATOR_CORE = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0, branches = { [2] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 } } },
            COOLANT_HOSE_FAILURE = { branches = {
                [1] = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 },
                [2] = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0 }
            } },
            EXPANSION_TANK_FAILURE = { ecu = "ENGINE", spn = 111, warning = 1, critical = 1 },
            ACCESSORY_BELT_FAILURE = { ecu = "DASHBOARD", spn = 167, warning = 18, critical = 1 },
            FAN_CLUTCH_FAILURE = { ecu = "ENGINE", spn = 1639, warning = 1, critical = 1, fanDrive = "ELECTRONIC" },
            BATTERY_SULFATION = { ecu = "ENGINE", spn = 168, warning = 1, critical = 1 },
            POWER_CABLE_CONNECTION_FAILURE = { ecu = "ENGINE", spn = 168, warning = 2, critical = 2 },
            STARTER_RELAY_FAILURE = { ecu = "ENGINE", spn = 677, warning = 5, critical = 5 },
            ALTERNATOR = { ecu = "DASHBOARD", spn = 167, warning = 18, critical = 1 },
            TRANSMISSION_PUMP_MALFUNCTION = { ecu = "TRANSMISSION", spn = 127, warning = 18, critical = 1 },
            HYDROSTATIC_UNIT_MALFUNCTION = { ecu = "TRANSMISSION", spn = 526, warning = 7, critical = 7 },
            CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = { ecu = "TRANSMISSION", spn = 526, warning = 7, critical = 7 },
            CVT_ADDON_MALFUNCTION = { ecu = "TRANSMISSION", spn = 526, warning = 7, critical = 7 },
            TRANSMISSION_OIL_COOLER_MALFUNCTION = { ecu = "TRANSMISSION", spn = 177, warning = 16, critical = 0 },
            TRANSMISSION_OIL_LEAK = { ecu = "TRANSMISSION", spn = 124, warning = 18, critical = 1 },
            HYDRAULIC_PUMP_MALFUNCTION = { ecu = "TRACTOR", spn = 1762, warning = 18, critical = 1 },
            HYDRAULIC_HOSE_EXTERNAL_LEAK = { ecu = "TRACTOR", spn = 2602, warning = 18, critical = 1 },
            HYDRAULIC_OIL_COOLER_MALFUNCTION = { ecu = "TRACTOR", spn = 1638, warning = 16, critical = 0, branches = { [2] = { ecu = "TRACTOR", spn = 2602, warning = 18, critical = 1 } } },
            HYDRAULIC_FILTER_CLOGGING = { ecu = "TRACTOR", spn = 1713, warning = 31, critical = 31 },
            PTO_ENGAGEMENT_SOLENOID_FAILURE = { branches = { [1] = { ecu = "TRACTOR", spn = 2910, warning = 5, critical = 5 } } },
            PTO_CLUTCH_WEAR = { ecu = "TRACTOR", spn = 1883, warning = 7, critical = 7 },
            FRONT_PTO_CLUTCH_FAILURE = { ecu = "TRACTOR", spn = 1882, warning = 7, critical = 7 },
            PTO_OUTPUT_SEAL_LEAK = { ecu = "TRANSMISSION", spn = 124, warning = 18, critical = 1 },
            PTO_OUTPUT_SHAFT_FAILURE = { ecu = "TRACTOR", spn = 1883, warning = 7, critical = 7 },
            PTO_BRAKE_FAILURE = { ecu = "TRACTOR", spn = 1883, warning = 7, critical = 7 },
            PTO_SPEED_SENSOR_FAILURE = { ecu = "TRACTOR", spn = 186, warning = 2, critical = 2 },
            BRAKE_CONTROL_FAILURE = { branches = { [2] = { ecu = "TRACTOR", spn = 116, warning = 18, critical = 1 } } },
            INVERTER_MALFUNCTION = { ecu = "INVERTER", spn = 9109, warning = 12, critical = 12 },
            ELECTRIC_MOTOR_WINDING_FAULT = { ecu = "INVERTER", spn = 9115, warning = 16, critical = 0 },
            ELECTRIC_MOTOR_BEARING_WEAR = { ecu = "INVERTER", spn = 9059, warning = 16, critical = 0 },
            MOTOR_POSITION_SENSOR_FAULT = { ecu = "INVERTER", spn = 9067, warning = 2, critical = 2 },
            DCDC_CONVERTER_FAILURE = { ecu = "CONVERTER", spn = 8585, warning = 18, critical = 1 },
            ONBOARD_CHARGER_FAILURE = { ecu = "CHARGER", spn = 4993, warning = 18, critical = 1 },
            HV_INSULATION_LOSS = { ecu = "TRACTION_BATTERY", spn = 8432, warning = 18, critical = 1 },
            TRACTION_BATTERY_CELL_FAULT = { ecu = "TRACTION_BATTERY", spn = 5923, warning = 18, critical = 1 },
            HV_CONTACTOR_FAILURE = { ecu = "TRACTION_BATTERY", spn = 8091, warning = 7, critical = 7 },
            -- Persistent states
            ENGINE_THERMAL_PROTECTION = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0 },
            OVERHEAT_PROTECTION = { ecu = "ENGINE", spn = 110, warning = 0, critical = 0,
                electric = { ecu = "INVERTER", spn = 9059 } },
            VOLTAGE_SAG = { ecu = "ENGINE", spn = 168, warning = 1, critical = 1 },
            POWERSHIFT_CLUTCH_FAILURE = { ecu = "TRANSMISSION", spn = 526, warning = 7, critical = 7 },
            POWERSHIFT_REVERSER_FAILURE = { ecu = "TRANSMISSION", spn = 526, warning = 7, critical = 7 },
            TRANSMISSION_CONTROL_FAILURE = { ecu = "TRANSMISSION", spn = 4217, warning = 7, critical = 7 },
            -- Output speed, clutch pressure.
            TRANSMISSION_SENSOR_FAILURE = { ecu = "TRANSMISSION", spn = 191, warning = 2, critical = 5,
                branches = { [2] = { ecu = "TRANSMISSION", spn = 127, warning = 3, critical = 5 } } },
            CVT_SENSOR_FAILURE = { ecu = "TRANSMISSION", spn = 191, warning = 2, critical = 5,
                branches = { [2] = { ecu = "TRANSMISSION", spn = 127, warning = 3, critical = 5 } } },
            FOUR_WD_CONTROL_FAILURE = { ecu = "TRACTOR", spn = 2612, warning = 7, critical = 7 },
            DIFF_LOCK_CONTROL_FAILURE = { ecu = "TRACTOR", spn = 569, warning = 7, critical = 7 },
            LIFT_VALVE_FAILURE = { ecu = "TRACTOR", spn = 4084, warning = 7, critical = 7 },
            LIFT_POSITION_SENSOR_FAILURE = { ecu = "TRACTOR", spn = 1873, warning = 2, critical = 2 },
            -- Redundant joystick input, supply.
            LOADER_CONTROL_FAILURE = { ecu = "TRACTOR", spn = 2660, warning = 14, critical = 4 },
            HYDRAULIC_CYLINDER_INTERNAL_LEAK = { branches = { [2] = { ecu = "TRACTOR", spn = 2602, warning = 18, critical = 1 } } },
            HYDRAULIC_QUICK_COUPLER_FAILURE = { branches = { [1] = { ecu = "TRACTOR", spn = 2602, warning = 18, critical = 1 } } },
        }
    },

    -- Electric drive
    ELECTRIC_DRIVE = {
        MOTOR_STANDSTILL_MULTIPLIER = 0.1,
        MOTOR_OVERLOADED_THRESHOLD = 0.90,
        MOTOR_OVERLOADED_MAX_EFFECT = 1.05,
        MOTOR_OVERLOADED_MULTIPLIER = 1.0,
        MOTOR_OVERHEAT_MULTIPLIER = 50.0,
        DEEP_DISCHARGE_THRESHOLD = 0.15,
        DEEP_DISCHARGE_MULTIPLIER = 3.0,
        HIGH_DRAW_THRESHOLD = 0.85,
        HIGH_DRAW_MULTIPLIER = 1.0,
        BATTERY_HEAT_THRESHOLD = 40,
        BATTERY_HEAT_FULL_EFFECT = 60,
        BATTERY_HEAT_MULTIPLIER = 10.0,

        -- Motor and inverter temperature limits
        THERMAL = {
            PID_TARGET_TEMP = 60,
            OVERHEAT_THRESHOLD = 70,
            OVERHEAT_FULL_EFFECT = 100,
            TELLTALE = { WARNING = 75, CRITICAL = 85 }
        },
        BATTERY_COLD_STAGES = { 10, 0, -10, -20 },

        BATTERY_CAPACITY_FADE = 0.20,
        CHARGE_ACCEPTANCE_CURVE = { { -10, 0.2 }, { 0, 0.5 }, { 10, 1.0 } },
        CHARGE_SLICE = 0.001
    },

    BRANDS = {
        FENDT = 1.2,
        JOHNDEERE = 1.2,
        VOLVO = 1.1,
        KOMATSU = 1.1,
        PONSSE = 1.1,
        ROTTNE = 1.1,
        CATERPILLAR = 1.1,
        KENWORTH = 1.1,
        PETERBILT = 1.1,
        SCHLUETER = 1.1,
        CLAAS = 1.1,
        ROPA = 1.1,
        HOLMER = 1.1,
        MACK = 1.1,
        KRONE = 1.1,
        KUBOTA = 1.1,
        MAN = 1.1,
        CHALLENGER = 1.1,
        AGCO = 1.1,
        MERCEDES = 1.1,
        MERCEDESBENZ = 1.1,
        MERCEDESBENZTRUCKS = 1.1,
        KRAMER = 1.1,
        VALTRA = 1.2,
        LINDNER = 1.1,
        GMC = 1.1,
        CASEIH = 1.1,
        NEWHOLLAND = 1.1,
        SDF = 1.1,
        MASSEYFERGUSON = 1.2,
        JCB = 1.1,
        DEUTZFAHR = 1.1,
        STEYR = 1.1,
        VERSATILE = 1.1,
        INTERNATIONAL = 1.1,
        FORD = 1.1,
        RENAULT = 1.1,
        INTERNATIONALHARVESTER = 1.1,
        LANDROVER = 1.0,
        NEXAT = 1.0,
        ZETOR = 1.0,
        FIAT = 1.1,
        LANDINI = 1.1,
        SAME = 1.1,
        MCCORMICK = 1.1,
        ARMATRAC = 1.1,
        MAHINDRA = 1.1,
        STARA = 1.1,
        PTZKIROWEC = 1.1,
        MTZ = 1.1,
        SKODA = 1.1,
        GAZ = 1.0,
        MAZ = 1.0,
        BUEHRER = 1.1,
        LTZ = 1.1,
        PORSCHEDIESEL = 1.1,
        OLIVER = 1.1,
        ALLISCHALMERS = 1.1,
        LIZARD = 1.0,
        GIANTS = 1.0,
        NONE = 1.0,
    },

    SERVICE_REFERENCE_HOURS = 500,
    SERVICE_ACCESS_PROFILES = {
        SIMPLE = {label = "rms_service_access_easy", shopLabel = "rms_shop_service_access_easy", transmission = 0.9},
        STANDARD = {label = "rms_service_access_average", shopLabel = "rms_shop_service_access_average"},
        COMPLEX = {label = "rms_service_access_demanding", shopLabel = "rms_shop_service_access_demanding", transmission = 1.25,
            diagnostic = 1.25}
    },
    SERVICE_PROGRAM = {
        engine = { hours = 500, months = 12 },
        transmission = { hours = 1000, months = 24 },
        hydraulic = { hours = 1000, months = 24 },
        coolant = { hours = 2000, months = 24 }
    },
    -- engine oil hours of a dated machine built before each year
    ENGINE_OIL_HOURS_BY_YEAR = {
        { before = 1960, hours = 100 },
        { before = 1980, hours = 220 },
        { before = 2000, hours = 250 },
        { before = 2010, hours = 400 }
    },

    TUTORIAL_MESSAGES = {
        SERVICE_DUE_SOON = false,
        SERVICE_INTERVAL_EXPIRED = false,
        RAD_OR_FILTER_CLOGGED = false,
        NEEDS_LUBRICATION = false,
        NEEDS_REPAIR = false,
        NEEDS_OVERHAUL = false,
        AGE_DEGRADATION = false,
        NEEDS_PREVENTIVE = false,
        POOR_CONSUMABLES = false,
        POOR_PARTS = false,
        IDLE_AND_DOWNTIME = false,
        HOT_WEATHER = false,
        WET_WEATHER = false,
        LOW_FUEL = false,
        IDLE_DEPOSIT = false,
        ENGINE_OVERHEAT = false,
        CVT_OVERHEAT = false,
        HEAVY_TRAILER = false,
        CHASSIS_VIBRATION = false,
        TERRAIN_IMPACT = false,
        DRIVETRAIN_WINDUP = false,
        STEERING = false,
        CRANKING = false,
        PREHEAT = false,
        BATTERY_LOW = false,
        HARD_START = false,
        CRITICAL_FAILURE = false,
        COLD_ENGINE = false,
        COLD_OIL = false,
        WHEEL_SLIP = false,
        OVERLOAD_INDICATOR = false,
        ENGINE_OVERLOAD = false,
        LUGGING = false,
        PTO_ENGAGEMENT = false,
        PTO_RAISED = false,
        FLUID_LEVEL = false,
        EXHAUST_SMOKE = false,
        DRIVETRAIN_MODES = false,
        PARK_BRAKE = false,
        PARK_BRAKE_MANUAL = false,
        TRANSMISSION_OVERHEAT = false,
    }
}

---Clears every seen flag of the tutorial messages
function RMS_Config.resetTutorialMessages()
    for messageId, _ in pairs(RMS_Config.TUTORIAL_MESSAGES) do
        RMS_Config.TUTORIAL_MESSAGES[messageId] = false
    end
end

RMS_Config.TUTORIAL_MESSAGE_IDS = {}
for messageId, _ in pairs(RMS_Config.TUTORIAL_MESSAGES) do
    table.insert(RMS_Config.TUTORIAL_MESSAGE_IDS, messageId)
end
table.sort(RMS_Config.TUTORIAL_MESSAGE_IDS)

RMS_Config.TUTORIAL_PLAYER_STATES = {}
RMS_Config.TUTORIAL_STATE_LOADED = false
RMS_Config.TUTORIAL_LOCAL_USER_ID = nil

---Builds a normalized tutorial state from its three parts
-- @param boolean? tutorialMode true while the tips are shown
-- @param boolean? welcomeMessageSeen true once the welcome dialog was answered
-- @param table? messages seen flag of each message
-- @return table state tutorial state
function RMS_Config.createTutorialState(tutorialMode, welcomeMessageSeen, messages)
    local state = {
        tutorialMode = tutorialMode ~= false,
        welcomeMessageSeen = welcomeMessageSeen == true,
        messages = {}
    }

    for _, messageId in ipairs(RMS_Config.TUTORIAL_MESSAGE_IDS) do
        state.messages[messageId] = messages ~= nil and messages[messageId] == true or false
    end

    return state
end

---Snapshots the current tutorial state
-- @return table state tutorial state
function RMS_Config.captureTutorialState()
    return RMS_Config.createTutorialState(
        RMS_Config.TUTORIAL_MODE,
        RMS_Config.WELCOME_MESSAGE_SEEN,
        RMS_Config.TUTORIAL_MESSAGES
    )
end

---Writes a tutorial state into the configuration
-- @param table? state tutorial state
function RMS_Config.applyTutorialState(state)
    local normalized = RMS_Config.createTutorialState(
        state ~= nil and state.tutorialMode or nil,
        state ~= nil and state.welcomeMessageSeen or nil,
        state ~= nil and state.messages or nil
    )

    RMS_Config.TUTORIAL_MODE = normalized.tutorialMode
    RMS_Config.WELCOME_MESSAGE_SEEN = normalized.welcomeMessageSeen
    for _, messageId in ipairs(RMS_Config.TUTORIAL_MESSAGE_IDS) do
        RMS_Config.TUTORIAL_MESSAGES[messageId] = normalized.messages[messageId]
    end
    RMS_Config.TUTORIAL_STATE_LOADED = true
end

---Resets the tutorial state of the local player
function RMS_Config.resetLocalTutorialState()
    RMS_Config.TUTORIAL_MODE = true
    RMS_Config.WELCOME_MESSAGE_SEEN = false
    for _, messageId in ipairs(RMS_Config.TUTORIAL_MESSAGE_IDS) do
        RMS_Config.TUTORIAL_MESSAGES[messageId] = false
    end
    RMS_Config.TUTORIAL_STATE_LOADED = false
    RMS_Config.TUTORIAL_LOCAL_USER_ID = nil
end

---Clears the tutorial states of every player for a new session
function RMS_Config.resetTutorialStateSession()
    RMS_Config.TUTORIAL_PLAYER_STATES = {}
    RMS_Config.resetLocalTutorialState()
end

---Returns the tutorial state stored for a player
-- @param string? uniqueUserId unique user id
-- @return table? state tutorial state
function RMS_Config.getTutorialPlayerState(uniqueUserId)
    if uniqueUserId == nil or uniqueUserId == "" then return nil end

    uniqueUserId = tostring(uniqueUserId)
    local state = RMS_Config.TUTORIAL_PLAYER_STATES[uniqueUserId]
    if state == nil then
        state = RMS_Config.createTutorialState()
        RMS_Config.TUTORIAL_PLAYER_STATES[uniqueUserId] = state
    end
    return RMS_Config.createTutorialState(state.tutorialMode, state.welcomeMessageSeen, state.messages)
end

---Stores the tutorial state of a player
-- @param string? uniqueUserId unique user id
-- @param table? state tutorial state
function RMS_Config.setTutorialPlayerState(uniqueUserId, state)
    if uniqueUserId == nil or uniqueUserId == "" or state == nil then return end
    RMS_Config.TUTORIAL_PLAYER_STATES[tostring(uniqueUserId)] = RMS_Config.createTutorialState(
        state.tutorialMode,
        state.welcomeMessageSeen,
        state.messages
    )
end

---Creates the tutorial state of the local player on first use
function RMS_Config.ensureLocalTutorialState()
    if RMS_Config.TUTORIAL_STATE_LOADED then return true end
    if g_server == nil or g_localPlayer == nil then return false end

    local uniqueUserId = g_localPlayer:getUniqueId()
    local state = RMS_Config.getTutorialPlayerState(uniqueUserId)
    if state == nil then return false end

    RMS_Config.TUTORIAL_LOCAL_USER_ID = uniqueUserId
    RMS_Config.applyTutorialState(state)
    return true
end

---Replicates the tutorial state between the server and the client
function RMS_Config.syncTutorialState()
    if not RMS_Config.TUTORIAL_STATE_LOADED and not RMS_Config.ensureLocalTutorialState() then return end

    local state = RMS_Config.captureTutorialState()
    if g_server ~= nil then
        RMS_Config.setTutorialPlayerState(RMS_Config.TUTORIAL_LOCAL_USER_ID, state)
    else
        RMS_TutorialStateEvent.sendToServer(state)
    end
end

RMS_Config.savegameFile = "realisticMechanicalSystems.xml"

---Prints a debug line while debug mode is on
local function log_dbg(...)
    if RMS_Config.DEBUG then
        local args = {...}
        for i = 1, #args do args[i] = tostring(args[i]) end
        print("[RMS_CFG] " .. table.concat(args, " "))
    end
end

---Writes the tutorial state of every player to the settings file
local function saveTutorialPlayerStates(xmlFile, root)
    local userIds = {}
    for uniqueUserId, _ in pairs(RMS_Config.TUTORIAL_PLAYER_STATES) do
        table.insert(userIds, uniqueUserId)
    end
    table.sort(userIds)

    for index, uniqueUserId in ipairs(userIds) do
        local state = RMS_Config.TUTORIAL_PLAYER_STATES[uniqueUserId]
        local key = string.format("%s.tutorialPlayers.player(%d)", root, index - 1)
        setXMLString(xmlFile, key .. "#uniqueUserId", uniqueUserId)
        setXMLBool(xmlFile, key .. ".tutorialMode", state.tutorialMode)
        setXMLBool(xmlFile, key .. ".welcomeMessageSeen", state.welcomeMessageSeen)
        for _, messageId in ipairs(RMS_Config.TUTORIAL_MESSAGE_IDS) do
            setXMLBool(xmlFile, key .. ".messages." .. messageId, state.messages[messageId] == true)
        end
    end
end

---Reads the tutorial state of every player from the settings file
local function loadTutorialPlayerStates(xmlFile, root)
    RMS_Config.TUTORIAL_PLAYER_STATES = {}
    local index = 0

    while true do
        local key = string.format("%s.tutorialPlayers.player(%d)", root, index)
        local uniqueUserId = getXMLString(xmlFile, key .. "#uniqueUserId")
        if uniqueUserId == nil then break end

        local messages = {}
        for _, messageId in ipairs(RMS_Config.TUTORIAL_MESSAGE_IDS) do
            messages[messageId] = getXMLBool(xmlFile, key .. ".messages." .. messageId) == true
        end
        RMS_Config.setTutorialPlayerState(uniqueUserId, {
            tutorialMode = getXMLBool(xmlFile, key .. ".tutorialMode"),
            welcomeMessageSeen = getXMLBool(xmlFile, key .. ".welcomeMessageSeen"),
            messages = messages
        })
        index = index + 1
    end
end

---Writes every adjustable setting to a settings file
local function writeConfigFile(xmlFileName, includeTutorialStates)
    local xmlFile = createXMLFile("realisticMechanicalSystems", xmlFileName, "realisticMechanicalSystems")
    if xmlFile == nil or xmlFile == 0 then
        log_dbg("SAVE ERROR - createXMLFile returned", tostring(xmlFile))
        return false
    end

    local root = "realisticMechanicalSystems"
    setXMLInt(xmlFile, root .. "#saveVersion", RMS_Config.CONFIG_VERSION)

    -- core
    setXMLFloat(xmlFile, root .. ".BASE_SERVICE_WEAR",      RMS_Config.CORE.BASE_SERVICE_WEAR)
    setXMLFloat(xmlFile, root .. ".BASE_SYSTEMS_WEAR",      RMS_Config.CORE.BASE_SYSTEMS_WEAR)
    setXMLBool (xmlFile, root .. ".ENABLE_WARNING_MESSAGES", RMS_Config.CORE.ENABLE_WARNING_MESSAGES)

    -- maintenance
    setXMLBool (xmlFile, root .. ".INSTANT_INSPECTION",     RMS_Config.MAINTENANCE.INSTANT_INSPECTION)
    setXMLBool (xmlFile, root .. ".INSTANT_MAINTENANCE_REPAIR", RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR)
    setXMLBool (xmlFile, root .. ".INSTANT_BODYWORK", RMS_Config.MAINTENANCE.INSTANT_BODYWORK)
    setXMLBool (xmlFile, root .. ".INSTANT_OVERHAUL", RMS_Config.MAINTENANCE.INSTANT_OVERHAUL)

    -- workshop
    setXMLBool (xmlFile, root .. ".DEALER_ALWAYS_AVAILABLE",       RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE)
    setXMLBool (xmlFile, root .. ".MOBILE_ALWAYS_AVAILABLE",       RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE)
    setXMLBool (xmlFile, root .. ".OWN_ALWAYS_AVAILABLE",          RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE)
    setXMLBool (xmlFile, root .. ".MOBILE_WORKSHOP_RESTRICTIONS_ENABLED", RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED)
    setXMLFloat(xmlFile, root .. ".OPEN_HOUR",              RMS_Config.WORKSHOP.OPEN_HOUR)
    setXMLFloat(xmlFile, root .. ".CLOSE_HOUR",             RMS_Config.WORKSHOP.CLOSE_HOUR)

    -- thermal

    -- drivetrain
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_ENABLED",           RMS_Config.DRIVETRAIN.ENABLED)
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_ALLOW_AUTO_MODE",   RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE)
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_PARKBRAKE_ENABLED", RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED)

    -- exhaust
    setXMLBool (xmlFile, root .. ".EXHAUST_SMOKE_ENABLED",   RMS_Config.EXHAUST.ENABLED)

    -- debug
    setXMLBool (xmlFile, root .. ".DEBUG_MODE",             RMS_Config.DEBUG)

    if includeTutorialStates then
        if RMS_Config.TUTORIAL_STATE_LOADED and RMS_Config.TUTORIAL_LOCAL_USER_ID ~= nil then
            RMS_Config.setTutorialPlayerState(RMS_Config.TUTORIAL_LOCAL_USER_ID, RMS_Config.captureTutorialState())
        end
        saveTutorialPlayerStates(xmlFile, root)
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
    return true
end

---Writes every adjustable setting to the savegame file
-- @return boolean written true once the file is written
function RMS_Config.saveToXMLFile()
    if not g_currentMission:getIsServer() then
        return false
    end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end

    local savegameWritten = writeConfigFile(savegameFolderPath .. "/" .. RMS_Config.savegameFile, true)

    return savegameWritten
end

---Reads every adjustable setting from the savegame settings file
function RMS_Config.loadFromXMLFile()
    if RMS_Config._loaded then
        return
    end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end

    local xmlFileName = savegameFolderPath .. "/" .. RMS_Config.savegameFile
    if not fileExists(xmlFileName) then
        return
    end

    local xmlFile = loadXMLFile("realisticMechanicalSystems", xmlFileName)
    if xmlFile == nil or xmlFile == 0 then
        log_dbg("LOAD ERROR - loadXMLFile returned", tostring(xmlFile))
        return
    end

    local root = "realisticMechanicalSystems"
    RMS_Config.loadedConfigVersion = getXMLInt(xmlFile, root .. "#saveVersion") or 0
    log_dbg("LOAD VERSION", RMS_Config.loadedConfigVersion, "CURRENT", RMS_Config.CONFIG_VERSION)
    local v

    -- core
    v = getXMLFloat(xmlFile, root .. ".BASE_SERVICE_WEAR")
    if v ~= nil then RMS_Config.CORE.BASE_SERVICE_WEAR = v end

    v = getXMLFloat(xmlFile, root .. ".BASE_SYSTEMS_WEAR")
    if v ~= nil then RMS_Config.CORE.BASE_SYSTEMS_WEAR = v end

    v = getXMLBool(xmlFile, root .. ".ENABLE_WARNING_MESSAGES")
    if v ~= nil then RMS_Config.CORE.ENABLE_WARNING_MESSAGES = v end

    -- maintenance
    v = getXMLBool(xmlFile, root .. ".INSTANT_INSPECTION")
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_INSPECTION = v end

    v = getXMLBool(xmlFile, root .. ".INSTANT_MAINTENANCE_REPAIR")
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR = v end

    v = getXMLBool(xmlFile, root .. ".INSTANT_BODYWORK")
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_BODYWORK = v end

    v = getXMLBool(xmlFile, root .. ".INSTANT_OVERHAUL")
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_OVERHAUL = v end

    -- workshop
    v = getXMLBool(xmlFile, root .. ".DEALER_ALWAYS_AVAILABLE")
    if v ~= nil then RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE = v end

    v = getXMLBool(xmlFile, root .. ".MOBILE_ALWAYS_AVAILABLE")
    if v ~= nil then RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE = v end

    v = getXMLBool(xmlFile, root .. ".OWN_ALWAYS_AVAILABLE")
    if v ~= nil then RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE = v end

    v = getXMLBool(xmlFile, root .. ".MOBILE_WORKSHOP_RESTRICTIONS_ENABLED")
    if v ~= nil then RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED = v end

    v = getXMLFloat(xmlFile, root .. ".OPEN_HOUR")
    if v ~= nil then RMS_Config.WORKSHOP.OPEN_HOUR = v end

    v = getXMLFloat(xmlFile, root .. ".CLOSE_HOUR")
    if v ~= nil then RMS_Config.WORKSHOP.CLOSE_HOUR = v end

    -- drivetrain
    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_ENABLED")
    if v ~= nil then RMS_Config.DRIVETRAIN.ENABLED = v end

    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_ALLOW_AUTO_MODE")
    if v ~= nil then RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE = v end


    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_PARKBRAKE_ENABLED")
    if v ~= nil then RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED = v end

    -- exhaust
    v = getXMLBool(xmlFile, root .. ".EXHAUST_SMOKE_ENABLED")
    if v ~= nil then RMS_Config.EXHAUST.ENABLED = v end


    -- debug
    v = getXMLBool(xmlFile, root .. ".DEBUG_MODE")
    if v ~= nil then RMS_Config.DEBUG = v end

    if g_currentMission:getIsServer() then
        loadTutorialPlayerStates(xmlFile, root)
    end

    RMS_Config.applyLoadedVersion()
    delete(xmlFile)
    RMS_Config._loaded = true
end

---Compares a loaded settings file with the current configuration format
function RMS_Config.applyLoadedVersion()
    local loadedVersion = tonumber(RMS_Config.loadedConfigVersion) or 0
    local currentVersion = RMS_Config.CONFIG_VERSION
    if loadedVersion > currentVersion then
        Logging.warning("RMS: settings file version %d is newer than supported %d", loadedVersion, currentVersion)
    end
end
