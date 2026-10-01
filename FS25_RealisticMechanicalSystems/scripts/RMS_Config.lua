-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Every tunable value of the mod, and the load and save of the settings file
RMS_Config = {
    CONFIG_VERSION = 1,

    -- extensive debug logging in the console
    DEBUG = false,
    TUTORIAL_MODE = true,

    -- update interval of the responsive effects, in ms
    ON_UPDATE_DELAY = 100, -- (100ms = 10 times per second)
    TUTORIAL_UPDATE_DELAY = 1000, -- (60 seconds)

    UPDATE_VEHICLE_STATE_DELAY_ONE = 50,
    UPDATE_VEHICLE_STATE_DELAY_TWO = 200,
    UPDATE_VEHICLE_STATE_DELAY_THREE = 500,
    ROOF_RAYCAST_INTERVAL = 5000,
    ROOF_RAYCAST_DISTANCE = 40,
    ROOF_RAYCAST_START_OFFSET = 1,
    ROOF_STATIONARY_SPEED_LIMIT = 0.5,
    
    -- update interval of the wear and thermal simulation, in ms
    CORE_UPDATE_DELAY = 250,
    META_UPDATE_DELAY = 30000,

    -- wear, stress and breakdown probability
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

        ENGINE_FACTOR_DATA = {
            MOTOR_IDLING_MULTIPLIER = 0.5,
            SERVICE_EXPIRED_MULTIPLIER = 6.0,
            MOTOR_IDLING_THRESHOLD = 0.3,
            MOTOR_OVERLOADED_MULTIPLIER = 1.5, 
            MOTOR_OVERLOADED_THRESHOLD = 0.85,
            MOTOR_OVERLOADED_MAX_EFFECT = 1.05,
            LUGGING_MULTIPLIER = 3.0,       
            LUGGING_RPM_THRESHOLD = 0.6,
            LUGGING_MOTORLOAD_THRESHOLD = 0.80,
            COLD_MOTOR_RPM_INFLUENCE = 0.35,
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
            PULL_OVERLOAD_THRESHOLD = 0.85,
            PULL_OVERLOAD_TIMER_THRESHOLD = 60,
            PULL_OVERLOAD_TIMER_MAX_EFFECT = 90,
            LUGGING_MULTIPLIER = 10.0,
            LUGGING_RPM_THRESHOLD = 0.6,
            LUGGING_MOTORLOAD_THRESHOLD = 0.80,
            WHEEL_SLIP_MULTIPLIER = 10.0,        
            WHEEL_SLIP_THRESHOLD = 0.05,
            HEAVY_TRAILER_MULTIPLIER = 2.0,
            HEAVY_TRAILER_MASS_RATIO_THRESHOLD = 10.0,
            HEAVY_TRAILER_MASS_RATIO_FULL_EFFECT = 5.0,
            HEAVY_TRAILER_TRUCK_MASS_RATIO_THRESHOLD = 6.0,
            HEAVY_TRAILER_TRUCK_MASS_RATIO_FULL_EFFECT = 3.0,
            HEAVY_TRAILER_MOTORLOAD_THRESHOLD = 0.7,
            -- share of the heavy trailer threshold firing the tutorial tip
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
            HOT_OIL_THRESHOLD = 90
        },

        PTO_FACTOR_DATA = {
            SERVICE_EXPIRED_MULTIPLIER = 4.0,
            -- share of the torque the engine can pass to the PTO a sustained load starts to strain the driveline at
            LOAD_FACTOR_THRESHOLD = 0.40,
            LOAD_FACTOR_FULL_EFFECT = 0.90,
            LOAD_FACTOR_MULTIPLIER = 6.0,
            -- past that capacity the engine bogs and the driveline takes the torque peaks
            OVERLOAD_FACTOR_FULL_EFFECT = 1.20,
            OVERLOAD_FACTOR_MULTIPLIER = 12.0,
            -- a liftable implement turning while raised drives the cardan joints at a steep angle
            RAISED_IMPLEMENT_MULTIPLIER = 4.0,
            -- time raised and turning before the tutorial explains it, longer than a headland turn
            RAISED_TUTORIAL_MS = 20000,
            -- condition every engagement takes from the clutch pack
            ENGAGEMENT_CLUTCH_DAMAGE = 0.0002,
            -- engaging above idle shocks the driveline: share of the idle to max rpm range it starts at,
            -- condition taken at full engine speed by an implement sized to the engine, and the smallest size counted
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
            VIB_FACTOR_MULTIPLIER = 36.0,
            VIB_FIELD_MULTIPLIER = 2.0
        },

        CHASSIS_FACTOR_DATA = {
            CHASSIS_IDLING_MULTIPLIER = 0.5,
            LUBRICATION_FACTOR_MULTIPLIER = 5.0,
            VIB_FACTOR_THRESHOLD = 0.08,
            VIB_FACTOR_MAX_SIGNAL = 0.36,
            VIB_FACTOR_MULTIPLIER = 36.0,
            VIB_FIELD_MULTIPLIER = 2.0,
            STEER_LOAD_FACTOR_MULTIPLIER = 2.0,
            STEER_LOAD_SPEED_THRESHOLD = 4.0,
            STEER_LOAD_RATE_DEADZONE = 0.02,
            STEER_LOAD_AXLE_RATIO_MAX = 3.0,
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

        STRESS_COOLDOWN = 0.5,
        CONDITION_EFFECTIVE_FLOOR = 0.10,
        REPEAT_BREAKDOWN_TIME = 1.3 * 3600000,
        USED_VEHICLE_BREAKDOWN_PRESENCE_CHANGE_MUL = 0.90,
        USED_VEHICLE_BREAKDOWN_PRESENCE_CHANGE_MAX = 0.66,

        CONCURRENT_BREAKDOWN_LIMIT_PER_VEHICLE = 15,
        ENABLE_WARNING_MESSAGES = true,

        -- the AI worker eases off like a careful driver once the machine runs into overload
        AI_WORKER = {
            -- km/h, the game's own field work floor
            MIN_SPEED = 5,
            -- shares of the overload warning level
            SLOW_DOWN_LEVEL = 0.5,
            RESUME_LEVEL = 0.25,
            -- km/h per second
            SLOW_DOWN_RATE = 1.0,
            RESUME_RATE = 0.5,
            -- km/h above the helper's own pace at which the limit lets go
            RELEASE_MARGIN = 3,
            -- seconds
            OVERLOAD_SMOOTHING = 2
        },
        GENERAL_WEAR_ENABLED = true,
        GENERAL_WEAR_EARLY_STAGE_THRESHOLD = 0.66,
        GENERAL_WEAR_LATE_STAGE_THRESHOLD = 0.33,

        RELIABILITY_YEAR_FACTOR = 0.01,
        RELIABILITY_YEAR_FACTOR_THRESHOLD = 2000,

        -- engine power counting as turbocharged, in kw
        TURBO_MIN_POWER_KW = 56,

        BASE_BREAKDOWN_PROGRESS_TIME = 1 * 3600000,
        BREAKDOWN_PROBABILITIES = {
            STRESS_THRESHOLD = 0.5,
            MIN_MTBF = 30,
            MAX_MTBF = 5200,
            DEGREE = 3.0,
            CRITICAL_MIN = 0.05,
            CRITICAL_MAX = 0.33,
            CRITICAL_DEGREE = 5
        },
    },

    -- workshop opening hours and availability
    WORKSHOP = {
        DEALER_ALWAYS_AVAILABLE = false,
        MOBILE_ALWAYS_AVAILABLE = true,
        OWN_ALWAYS_AVAILABLE = true,
        -- hour of the day the workshop opens
        OPEN_HOUR = 8,  -- (8 AM)
        -- hour of the day the workshop closes
        CLOSE_HOUR = 19, -- (7 PM)
        PRICE_MULTIPLIERS = {
            DEALER = 1.0,
            MOBILE = 1.2,
            OWN    = 0.8,
        },

        MOBILE_WORKSHOP_RESTRICTIONS_ENABLED = true,
        MOBILE_WORKSHOP_SERVICES_BY_MAINTAINABILITY = {
            INSPECTION = {
                STANDARD = 0.0,
                VISUAL   = 0.0,
                COMPLETE = 99.0,
            },

            MAINTENANCE = {
                STANDARD   = 1.1,
                EXTENDED   = 1.2,
                PREVENTIVE = 1.4,
            },

            REPAIR = {
                LOW    = 0.0,
                MEDIUM = 1.1,
                HIGH   = 99.0,
            },

            OVERHAUL = {
                STANDARD = 99.0,
                PARTIAL  = 99.0,
                FULL     = 99.0,
            },
        }
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
        MAINTENANCE_TIME = 6 * 3600000,
        MAINTENANCE_TIME_MULTIPLIERS = {
            STANDARD   = 1.0,
            EXTENDED   = 1.5,
            PREVENTIVE = 2.0,
        },
        REPAIR_TIME = 4 * 3600000,
        REPAIR_TIME_MULTIPLIERS = {
            LOW    = 0.2,
            MEDIUM = 1.0,
            HIGH   = 2.0,
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

        MAINTENANCE_PREVENTIVE_STRESS_REMOVE_MULTIPLIER = 0.6,
        MAINTENANCE_PREVENTIVE_SYSTEMS_COUNT = 3,

        REPAIR_REMAINING_STRESS_RATIO = {
            MEDIUM = 0.5,
            HIGH   = 0.0,
        },

        OVERHAUL_CONDITION_TARGETS = {
            STANDARD = 0.75,
            PARTIAL  = 0.75,
            FULL     = 1.0,
        },

        PARTS_BREAKDOWN_CHANCES = {
            OEM         = 0.1,
            USED        = 0.5,
            AFTERMARKET = 0.33,
            PREMIUM     = 0.0,
        },


        PARTS_PRICE_MULTIPLIERS = {
            OEM         = 1.0,
            USED        = 0.33,
            AFTERMARKET = 0.66,
            PREMIUM     = 1.20,
        },
        -- prices are real ones for a machine of this power, the engine sizing them and the game's cost multiplier
        -- scaling them with the economic difficulty; the service interval, not the price, carries the game's pace
        REFERENCE_POWER = 160,
        -- a dealer's hourly rate in euros
        LABOUR_RATE = 90,
        -- how labour and parts follow the engine power, measured on filter kits from 75 to 430 hp
        LABOUR_POWER_EXPONENT = 0.4,
        PARTS_POWER_EXPONENT = 0.6,
        -- labour, filters and parts of a road vehicle against a machine of the same power
        PROFILE_PRICE_FACTORS = {
            ROAD_LIGHT = { labour = 0.3,  filters = 0.2, parts = 0.5  },
            ROAD_HEAVY = { labour = 0.55, filters = 0.2, parts = 0.75 },
        },
        -- a real dealer's maintenance of the reference machine, fluids apart: labour hours and filters in euros
        MAINTENANCE_LABOUR_HOURS = {
            STANDARD   = 2.5,
            EXTENDED   = 5.0,
            PREVENTIVE = 8.0,
        },
        MAINTENANCE_FILTER_PRICES = {
            STANDARD   = 250,
            EXTENDED   = 550,
            PREVENTIVE = 700,
        },
        -- real value of the reference machine the breakdown registry's repair percentages and the overhauls apply to
        REPAIR_REFERENCE_VALUE = 57700,
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
    -- engine and transmission temperature model
    THERMAL = {
        -- shared thermal physics

        -- user multiplier of the engine temperature change rate
        TEMPERATURE_CHANGE_SPEED = 1.4,

        -- speed at which airflow cooling starts, in km/h
        SPEED_COOLING_MIN_SPEED = 15,
        -- speed at which airflow cooling peaks, in km/h
        SPEED_COOLING_MAX_SPEED = 50,
        -- peak airflow cooling factor
        SPEED_COOLING_MAX_EFFECT = 0.3,

        -- convection cooling rate while stationary
        CONVECTION_FACTOR = 0.0005,
        -- exponent applied to the gap with ambient, above 1 a hotter vehicle cools disproportionately faster
        DELTATEMP_FACTOR_DEGREE = 1.25,

        -- share of the radiator effectiveness a fully dirty vehicle loses
        MAX_DIRT_INFLUENCE = 1.0,
        
        -- time constant of the temperature gauge filter
        TAU = 5000,

        -- engine thermal values

        -- engine heat at full load
        ENGINE_MAX_HEAT = 1.05,
        -- engine heat at idle
        ENGINE_MIN_HEAT = 0.4,
        -- base engine temperature change rate before the user multiplier
        ENGINE_TEMPERATURE_CHANGE_SPEED = 0.35,
        -- temperature the engine thermostat starts opening at, in degrees
        ENGINE_THERMOSTAT_MIN_TEMP = 80,
        -- radiator cooling with the thermostat closed
        ENGINE_RADIATOR_MIN_COOLING = 0.0005,
        -- radiator cooling with the thermostat open
        ENGINE_RADIATOR_MAX_COOLING = 0.005,

        -- transmission thermal values

        -- transmission heat at full load
        TRANS_MAX_HEAT = 1.05,
        -- oil circulation and churning heat at low idle
        TRANS_IDLE_HEAT = 0.06,
        -- pump loss heat, produced whenever the motor turns
        TRANS_PUMP_HEAT = 0.03,
        -- share of the pto load that heats the shared oil
        TRANS_PTO_HEAT_SHARE = 0.15,
        -- extra load heat at a standstill, where the hydrostatic path carries the power
        TRANS_HYDROSTATIC_MAX_BOOST = 0.8,
        -- speed above which the mechanical path carries the power, in km/h
        TRANS_HYDROSTATIC_MAX_SPEED = 10,
        -- base transmission temperature change rate before the user multiplier
        TRANS_TEMPERATURE_CHANGE_SPEED = 0.14,
        TRANS_TEMPERATURE_CHANGE_MULTIPLIER = 1.0,
        HYDRAULIC_OPERATING_HEAT = 0.15,
        -- temperature the thermostat starts letting oil into the cooler, in degrees
        TRANS_THERMOSTAT_MIN_TEMP = 45,
        -- temperature the cooler runs at full flow, in degrees
        TRANS_THERMOSTAT_MAX_TEMP = 70,
        -- degrees a fully worn thermostat waits before it opens
        TRANS_THERMOSTAT_HEALTH_LAG = 30,
        -- oil cooler capacity at full flow
        TRANS_COOLER_MAX_COOLING = 0.0035,
        -- temperature the fan reaches its maximum at, in degrees
        TRANS_FAN_MAX_TEMP = 95,
        -- extra cooler capacity brought by the fan at its maximum
        TRANS_FAN_MAX_BOOST = 0.4,

        -- temperature the engine thermostat controller aims at, in degrees
        PID_TARGET_TEMP = 90,
        -- proportional gain, reacting to the current error
        PID_KP_MAX = 0.4,
        PID_KP_MIN = 0.1,
        -- integral gain, correcting a lasting error
        PID_KI = 0.02,
        -- derivative gain, damping the reaction
        PID_KD = 1.8,
        -- cap on the integral term
        PID_MAX_INTEGRAL = 200,

        -- natural cooling slowdown below the regulated temperature, by thermal mass
        ENGINE_COOLING_SLOWDOWN_POWER = 3.0,
        TRANS_COOLING_SLOWDOWN_POWER = 1.5,

        THERMOSTAT_TYPE_YEAR_DIVIDER = 2000,
        MECHANIC_THERMOSTAT_MIN_YEAR = 1950,
        ELECTRONIC_THERMOSTAT_MAX_YEAR = 2025,

        MECHANIC_THERMOSTAT_MIN_WAX_SPEED = 0.025,
        MECHANIC_THERMOSTAT_MAX_STICTION = 0.1,
        MECHANIC_THERMOSTAT_WAX_YEAR_SLOPE = 0.0005,

        ELECTRONIC_THERMOSTAT_MIN_WAX_SPEED = 0.05,
        ELECTRONIC_THERMOSTAT_MAX_WAX_SPEED = 0.10,
        ELECTRONIC_THERMOSTAT_MIN_STICTION = 0.01,
        ELECTRONIC_THERMOSTAT_MAX_STICTION = 0.05,
        ELECTRONIC_THERMOSTAT_WAX_YEAR_SLOPE = 0.0016,

        STICTION_YEAR_SLOPE = 0.0016
    },

    FIELD_CARE = {
        CLEANING_SPEED = 0.05,
        AIR_FILTER_BREAKDOWN_THRESHOLD = 0.5,
        AIR_FILTER_BLOWOUT_RESIDUE_SHARE = 0.25,
        -- Decoded length of sounds/inspection.ogg at pitch 1.0.
        VISUAL_INSPECTION_DURATION = 6850,
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

    -- engine oil, coolant, transmission oil and hydraulic fluid levels
    FLUIDS = {
        -- exact normalized vehicle XML keys take precedence over category profiles
        CAPACITY_OVERRIDES = {},

        -- engine oil burnt over one service interval by a healthy engine
        ENGINE_OIL_CONSUMPTION_PER_INTERVAL = 0.03,
        -- extra consumption of a fully worn engine
        ENGINE_OIL_WEAR_CONSUMPTION = 3.0,
        -- share of the consumption that follows the motor load
        ENGINE_OIL_LOAD_SHARE = 1.5,

        -- minimum mark of the gauge, the level the check asks for a top up at
        LEVEL_MIN_MARK = 0.85,
        -- levels the inspection reports under the mark
        LEVEL_LOW = 0.70,
        LEVEL_VERY_LOW = 0.50,
        LEVEL_CRITICALLY_LOW = 0.30,
        -- cooling capacity left with an empty circuit
        MIN_COOLING_FACTOR = 0.15,
        -- wear multiplier of a system running dry
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

        WINDUP_DAMAGE_ENABLED = true,
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

        PARKBRAKE_ENABLED = true,
        PARKBRAKE_AUTO_MODE = true
    },

    -- exhaust smoke colour and opacity
    EXHAUST = {
        ENABLED = true,

        -- smoke tints, mixed by concentration and kept saturated so the colour reads as the diagnosis it is:
        -- black soot, blue burnt oil, white unburnt fuel, the off white of condensed water, and the colourless
        -- gas of a clean pipe
        SOOT_TINT = {0.020, 0.020, 0.025},
        OIL_TINT = {0.050, 0.090, 0.350},
        UNBURNT_TINT = {0.980, 0.980, 0.980},
        VAPOUR_TINT = {0.920, 0.930, 0.950},
        CLEAN_TINT = {0.780, 0.780, 0.780},

        -- extinction per channel, soot blocking the most light per unit of concentration
        K_SOOT = 1.50,
        K_OIL = 1.20,
        K_UNBURNT = 1.00,
        OPACITY_FLOOR = 0.03,

        -- aftertreatment, and the share of fault soot none of it can hold back
        DEF_SOOT_FACTOR = 0.20,
        METHANE_SOOT_FACTOR = 0.10,
        AFTERTREATMENT_FAULT_FLOOR = 0.35,

        FLOW_BOOST_GAIN = 0.60,

        -- plume asset, the sprite family a directory loaded once for the session
        PLUME_EMIT_SHAPE = "particles/exhaust/plumeEmitShape.i3d",
        PLUME_SPRITES = "soft",
        PLUME_DIRECTORY = "particles/exhaust/",
        PLUME_FILE = "plume.i3d",

        PUFF = {
            -- neighbours overlapping any point of the plume from the outlet on, what keeps it continuous instead
            -- of a string of puffs, and the bounds of the rate that holds it, in puffs per second and outlet
            OVERLAP_TARGET = 5,
            RATE_MIN = 8,
            RATE_MAX = 720,
            -- once the neighbours overlap more than needed, puffs retire in halves, fading into the ones that
            -- remain, up to this many halvings
            THIN_LEVEL_MAX = 6,
            -- exit speed in m/s: a floor while cranking, and the speed at full gas flow with the gas at its full
            -- load temperature, about 4 m/s at idle and 30 at full power through a pipe sized for the rated flow;
            -- and the share of it each puff leaves sideways at, for a ragged edge
            EXIT_SPEED_MIN = 2.0,
            EXIT_SPEED_FULL = 30.0,
            SPREAD_SHARE = 0.02,
            -- tailpipe diameter in metres per square root of kW, about 75 mm at 70 kW, 110 at 150 and 155 at 300,
            -- within bounds
            PIPE_DIAMETER_PER_SQRT_KW = 0.009,
            PIPE_DIAMETER_MIN = 0.06,
            PIPE_DIAMETER_MAX = 0.16,
            -- sprite width over the gas width it draws: the smoke texture reaches half its opacity at about 60 % of
            -- the sprite, so a sprite that wide shows the gas at its real width; the share of the sprite width the
            -- visible smoke reaches from its centre, which surfaces stop; and the widest a sprite grows far
            -- downstream, where a heavy plume has spread over metres
            SPRITE_GAS_RATIO = 1.65,
            RADIUS_SHARE = 0.45,
            SIZE_MAX = 8.0,
            -- width the gas gains per metre it travels through the air, the concentration width at half maximum
            -- of a round jet (half-width 0.11 per metre), and per metre of crosswind it takes in until the wind has
            -- bent it over
            JET_SPREAD = 0.22,
            JET_CROSS_SPREAD = 0.10,
            -- step in ms of the jet profile the spacing and the sprite growth are read on
            JET_PROFILE_STEP_MS = 50,
            -- growth the eddies of the air add in m/s, a floor and the crosswind mixing it
            GROWTH_BASE = 0.18,
            GROWTH_PER_WIND = 0.15,
            -- a sprite grows at one steady rate, fitted to the gas width over this share of its life, within bounds
            -- in ms: the plume schedule on its visible life, each thinning level on its own
            GROWTH_FIT_SHARE = 0.35,
            GROWTH_FIT_MIN_MS = 400,
            GROWTH_FIT_LEVEL_MIN_MS = 20,
            GROWTH_FIT_MAX_MS = 4000,
            -- speed the rising plume carries its puffs apart at even in still air, in m/s
            RISE_SPEED = 0.40,
            -- width at which the condensed water shows the model vapour, a few decimetres from the outlet where
            -- the gas has mixed with the cold air, the smoke opacity being read at the outlet itself
            REFERENCE_SIZE = 0.50,
            -- life bounds in ms, and the plume optical depth under which it no longer shows
            LIFE_MIN = 800,
            LIFE_MAX = 8000,
            TAU_VISIBLE = 0.02,
            -- how much of the sprite area the smoke texture covers, tuned in game
            SPRITE_ALPHA_GAIN = 1.60,
            -- relative change under which a puff is not rewritten, so a faint puff among many still thins
            ALPHA_EPSILON = 0.03,
            -- fade out drawn by RMS in ms for the puffs that reach the end of the visible plume, the sprite asset
            -- carrying no blend of its own since its blend times would scale with lifespans that differ a lot;
            -- the retiring puffs fade through the thinning, and a new one among five overlapping needs no fade in
            FADE_OUT_MS = 300,
            -- drag toward the surrounding air on top of entrainment, per second, a spent jet being a tracer; with
            -- the entrainment above it puts a jet in crossflow on the measured y/(rD) = 2.05 (x/rD)^0.28 path
            BASE_DAMPING = 1.20,
            -- crosswind in m/s from which that drag applies in full, and the share left in still air
            DAMPING_CROSS_SPEED = 2.0,
            DAMPING_FLOOR_SHARE = 0.30,
            -- share of the blocked speed a puff keeps sliding along a surface, and of the air speed the flow
            -- keeps once a surface turns it aside
            SURFACE_SPREAD = 0.06,
            SURFACE_FLOW_SHARE = 0.85,
            -- speed a puff that overlaps a surface eases off it at, in m/s, instead of jumping clear in one step
            SURFACE_PUSH_SPEED = 1.5,
            -- a puff wider than this also looks straight above itself for a roof, in metres
            ROOF_PROBE_MIN_RADIUS = 0.30,
            -- share of the wind left under a roof, how far around a sheltered vehicle its roof counts, in metres,
            -- how often a puff checks it, in ms, and how fast it feels the change
            SHELTER_WIND_SHARE = 0.15,
            SHELTER_RADIUS = 8.0,
            SHELTER_CHECK_MS = 200,
            SHELTER_TAU = 400,
            -- a building, a hedge or a tree line upwind keeps part of the wind off its lee: how far upwind of the
            -- outlet one is looked for and how high above it its top, in metres, the least wind worth it in m/s, the
            -- share of the wind left up to so many obstacle heights behind it, the heights by which it is back in
            -- full, how far above the top a puff is in the free wind again, and the height of the outlet above the
            -- ground assumed without terrain, in metres
            LEE_SEARCH_DISTANCE = 40,
            LEE_PROBE_HEIGHT = 30,
            LEE_MIN_WIND = 0.5,
            LEE_WIND_SHARE = 0.25,
            LEE_FULL_HEIGHTS = 2,
            LEE_RECOVERY_HEIGHTS = 10,
            LEE_TOP_BLEND = 1.5,
            LEE_GROUND_FALLBACK = 2.5,
            -- a raycast hit this close to its origin started inside the collider, in metres
            INSIDE_HIT_DISTANCE = 0.001,
            -- sprites one outlet may hold at once, the retired ones included until their sprite has died
            POOL_MAX = 400
        },

        -- exhaust gas temperature rise over the air in kelvin at the tailpipe, idle and full load, about 100 to
        -- 150 C at idle and 350 to 500 C at full power past the turbo, and the share a cold engine reaches; the
        -- excess heat is shared with the air the gas takes in, falling as a power of its width between the 1 of a
        -- jet and the 5/3 of a rising plume
        EGT = {
            RISE_IDLE_K = 120,
            RISE_FULL_K = 430,
            COLD_FACTOR = 0.45,
            DILUTION_EXPONENT = 1.30
        },

        -- eddies of the air in m/s, a floor plus a share of the wind speed, the vertical ones weaker near the
        -- ground, each octave a wavelength in metres, a frequency in hertz and a weight
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

        -- combustion water condensing in cold air: the ambient range it appears over in degrees, its optical
        -- depth, the humidity weights, the idle share of the fuel burnt, the extra of a cold engine, and the
        -- evaporation time in ms from the mildest to the coldest air
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

        -- a transient darkens the puffs it wakes and sends them out faster, the gas flow already rising
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

        -- burst edge tick in ms
        TUNE_INTERVAL = 80,

        -- particle culling distance, in metres
        PLUME_CLIP_DISTANCE = 150,

        -- channel smoothing time constants, in ms
        TINT_TAU = 900,
        RISE_TAU = 250,
        SOOT_RISE_TAU = 150,

        SOOT_FALL_TAU = 350,
        BURST_RISE_TAU = 40,
        FALL_TAU = 1200,
        VAPOUR_TAU = 1500,

        -- share of the era factor kept by fault smoke
        ERA_BREAKDOWN_FLOOR = 0.60,

        -- emission eras, the factor applying to normal smoke
        ERA_FACTORS = {
            {2001, 1.00},
            {2006, 0.70},
            {2011, 0.40},
            {2014, 0.25},
            {9999, 0.18}
        },

        -- emission eras of the unburnt channel, injection pressure and glow plugs improving far less than particulate control
        UNBURNT_ERA_FACTORS = {
            {2001, 1.00},
            {2006, 0.90},
            {2011, 0.80},
            {2014, 0.70},
            {9999, 0.60}
        },

        -- year and power bands counting as Stage V
        STAGE_V = {
            OUTER_POWER_YEAR = 2019,
            MID_POWER_YEAR = 2020,
            MIN_POWER_KW = 19,
            MID_POWER_MIN_KW = 56,
            MID_POWER_MAX_KW = 130,
            MAX_POWER_KW = 560,
            SOOT_FACTOR = 0.15
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
        -- mild preheating remains useful above the temperature where failed plugs can prevent a start
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

    ELECTRICAL = {
        BATTERY_NOMINAL_CAPACITY = 150,
        BATTERY_USABLE_CAPACITY_FACTOR = 0.1,
        AMBIENT_DEFAULT_C = 15,
        BATTERY_THERMAL_TAU_S = 600,
        BATTERY_THERMAL_CAPACITY_J_PER_K = 2400,
        ENGINE_BAY_COUPLING = 0.30,
        RINT_REF_OHM = 0.005,
        BATTERY_HEALTH_RINT_MAX_MULT = 3.0,
        OCV_EMPTY_V = 11.7,
        OCV_FULL_V = 12.7,
        BATTERY_CRANK_CURRENT_A = 250,
        GLOW_CIRCUIT_PROXY_LOAD_A = 50,
        BATTERY_CHARGE_RISE_PER_20A_V = 0.18,
        BATTERY_CHARGE_RISE_MAX_V = 1.6,
        BATTERY_CHARGE_TARGET_MAX_V = 14.4,
        BATTERY_CHARGE_IR_SCALE = 0.0,
        BATTERY_TERMINAL_MIN_V = 8.5,
        BATTERY_TERMINAL_MAX_V = 14.8,
        CHARGE_ACCEPT_TEMP_MIN_C = -15,
        CHARGE_ACCEPT_TEMP_MAX_C = 25,
        CHARGE_TAPER_SOC_START = 0.80,
        CHARGE_TAPER_SOC_END = 0.98,
        BATTERY_HEALTH_ACCEPTANCE_MIN = 0.35,
        ALT_MAX_OUTPUT = 100,
        ALT_IDLE_FACTOR = 0.30,
        ALT_RPM_CURVE = {
            {0.00, 0.30},
            {0.25, 0.55},
            {0.50, 0.80},
            {0.75, 0.95},
            {1.00, 1.00}
        },
        ALTERNATOR_REGULATED_VOLTAGE = 14.1, 
        ALTERNATOR_MIN_REGULATED_VOLTAGE = 13.6,
        SYSTEM_VOLTAGE_TAU_MS = 250,          
        BATTERY_VOLTAGE_TAU_MS = 300,      
        ALT_DEFICIT_SAG_PER_AMP = 0.045,
        ALT_HEALTH_REGULATION_THRESHOLD = 0.15,
        ALT_LOW_HEALTH_DEFICIT_MULT = 1.8,
        ALT_BATTERY_SUPPORT_GAIN = 0.45,
        ALT_SURPLUS_CHARGE_HEADROOM_V = 0.3,  
        MAX_SYSTEM_VOLTAGE = 14.4,
        MIN_SYSTEM_VOLTAGE = 9.0,
        IDLE_CURRENT_A = 0.5,
    },

    -- per brand reliability and maintainability, {reliability, maintainability}
    -- an unlisted brand uses 1.0 and 1.0
    BRANDS = {

            FENDT           = {1.25, 0.80}, 
            JOHNDEERE       = {1.25, 0.85},
            VOLVO           = {1.25, 0.90},
            KOMATSU         = {1.25, 0.95},
            PONSSE          = {1.20, 0.90}, 
            ROTTNE          = {1.20, 0.90},
            CATERPILLAR     = {1.25, 0.80},
            KENWORTH        = {1.20, 0.90},
            PETERBILT       = {1.20, 0.90},
            SCHLUETER       = {1.20, 0.95},

            CLAAS           = {1.15, 0.95},
            ROPA            = {1.15, 0.85},
            HOLMER          = {1.15, 0.85},
            MACK            = {1.15, 1.00},
            KRONE           = {1.10, 1.00},
            KUBOTA          = {1.15, 1.10},
            MAN             = {1.10, 0.95},
            CHALLENGER      = {1.10, 0.90},
            AGCO            = {1.10, 0.90},
            MERCEDES        = {1.10, 0.90},
            MERCEDESBENZ    = {1.10, 0.90},
            MERCEDESBENZTRUCKS    = {1.10, 0.90},
            KRAMER          = {1.10, 0.95},

            VALTRA          = {1.10, 1.05},
            LINDNER         = {1.05, 1.00},
            GMC             = {1.05, 1.05},
            CASEIH          = {1.00, 1.00},
            NEWHOLLAND      = {1.00, 1.00},
            SDF             = {1.00, 1.00},
            MASSEYFERGUSON  = {1.00, 1.05},
            JCB             = {1.00, 0.90},
            DEUTZFAHR       = {1.00, 1.00},
            STEYR           = {1.00, 0.95},
            VERSATILE       = {1.00, 1.15}, 
            INTERNATIONAL   = {1.00, 1.15},
            FORD            = {1.00, 1.10},
            RENAULT         = {1.00, 1.05},
            INTERNATIONALHARVESTER = {1.00, 1.15},
            LANDROVER       = {0.90, 0.90}, 
            NEXAT           = {0.95, 0.65},

            ZETOR           = {0.85, 1.35},
            FIAT            = {0.90, 1.20},
            LANDINI         = {0.90, 1.15},
            SAME            = {0.90, 1.15},
            MCCORMICK       = {0.90, 1.10},
            ARMATRAC        = {0.85, 1.20},
            MAHINDRA        = {0.85, 1.25},
            STARA           = {0.85, 1.15},
            
            PTZKIROWEC      = {0.85, 1.30},
            MTZ             = {0.80, 1.50},
            SKODA           = {0.85, 1.20},
            GAZ             = {0.80, 1.40},
            MAZ             = {0.80, 1.35},
            BUEHRER         = {0.80, 1.30},
            LTZ             = {0.75, 1.55},
            PORSCHEDIESEL   = {0.70, 1.30},
            OLIVER          = {0.85, 1.25}, 
            ALLISCHALMERS   = {0.85, 1.25},

            LIZARD          = {1.00, 1.00},
            GIANTS          = {1.00, 1.00},
            NONE            = {1.00, 1.00}
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
    elseif RMS_TutorialStateEvent ~= nil then
        RMS_TutorialStateEvent.sendToServer(state)
    end
end

RMS_Config.savegameFile = "realisticMechanicalSystems.xml"
RMS_Config.legacySavegameFile = "advancedDamageSystem.xml"
RMS_Config.sharedSettingsDirectory = "modSettings/FS25_RealisticMechanicalSystems/"

---Prints a debug line while debug mode is on
-- @param any ... values to print
local function log_dbg(...)
    if RMS_Config.DEBUG then
        local args = {...}
        for i = 1, #args do args[i] = tostring(args[i]) end
        print("[RMS_CFG] " .. table.concat(args, " "))
    end
end

---Writes the tutorial state of every player to the settings file
-- @param number xmlFile XML file handle
-- @param string root xml root key
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
-- @param number xmlFile XML file handle
-- @param string root xml root key
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
-- @param string xmlFileName settings file path
-- @param boolean includeTutorialStates true to write the tutorial progress as well
-- @return boolean written true once the file is written
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
    setXMLBool (xmlFile, root .. ".GENERAL_WEAR_ENABLED",   RMS_Config.CORE.GENERAL_WEAR_ENABLED)
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
    setXMLFloat(xmlFile, root .. ".TEMPERATURE_CHANGE_SPEED", RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED)
    setXMLFloat(xmlFile, root .. ".TRANS_TEMPERATURE_CHANGE_MULTIPLIER", RMS_Config.THERMAL.TRANS_TEMPERATURE_CHANGE_MULTIPLIER)
    setXMLFloat(xmlFile, root .. ".MAX_DIRT_INFLUENCE",     RMS_Config.THERMAL.MAX_DIRT_INFLUENCE)

    -- electrical
    setXMLFloat(xmlFile, root .. ".BATTERY_USABLE_CAPACITY_FACTOR", RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR)
    setXMLFloat(xmlFile, root .. ".ALT_MAX_OUTPUT",         RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT)
    setXMLFloat(xmlFile, root .. ".IDLE_CURRENT_A",         RMS_Config.ELECTRICAL.IDLE_CURRENT_A)

    -- drivetrain
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_ENABLED",           RMS_Config.DRIVETRAIN.ENABLED)
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_ALLOW_AUTO_MODE",   RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE)
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_WINDUP_DAMAGE",     RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED)
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_PARKBRAKE_ENABLED", RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED)
    setXMLBool (xmlFile, root .. ".DRIVETRAIN_PARKBRAKE_AUTO",    RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE)

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

---Returns the path of the settings file shared by the new savegames
-- @return string path shared settings file path
function RMS_Config.getSharedSettingsFilePath()
    return getUserProfileAppPath() .. RMS_Config.sharedSettingsDirectory .. RMS_Config.savegameFile
end

---Writes every adjustable setting to the savegame file, then to the shared one
-- @return boolean written true once both files are written
function RMS_Config.saveToXMLFile()
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return false
    end

    if g_currentMission.missionInfo == nil then
        log_dbg("SAVE ABORT - missionInfo is nil")
        return false
    end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end

    local savegameWritten = writeConfigFile(savegameFolderPath .. "/" .. RMS_Config.savegameFile, true)

    createFolder(getUserProfileAppPath() .. RMS_Config.sharedSettingsDirectory)
    local sharedWritten = writeConfigFile(RMS_Config.getSharedSettingsFilePath(), false)

    return savegameWritten and sharedWritten
end

---Reads every adjustable setting from the savegame settings file
function RMS_Config.loadFromXMLFile()
    if RMS_Config._loaded then
        return
    end

    if g_currentMission == nil then
        log_dbg("LOAD SKIP - g_currentMission is nil")
        return
    end

    if g_currentMission.missionInfo == nil then
        log_dbg("LOAD SKIP - missionInfo is nil")
        return
    end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end

    local xmlFileName = savegameFolderPath .. "/" .. RMS_Config.savegameFile

    local isLegacyFile = false
    if not fileExists(xmlFileName) then
        xmlFileName = savegameFolderPath .. "/" .. RMS_Config.legacySavegameFile
        isLegacyFile = fileExists(xmlFileName)
    end

    if not fileExists(xmlFileName) then
        xmlFileName = RMS_Config.getSharedSettingsFilePath()
    end

    if not fileExists(xmlFileName) then
        return
    end

    local xmlFile = loadXMLFile("realisticMechanicalSystems", xmlFileName)
    if xmlFile == nil or xmlFile == 0 then
        log_dbg("LOAD ERROR - loadXMLFile returned", tostring(xmlFile))
        return
    end

    local root = isLegacyFile and "advancedDamageSystem" or "realisticMechanicalSystems"
    RMS_Config.loadedConfigVersion = getXMLInt(xmlFile, root .. "#saveVersion") or 0
    log_dbg("LOAD VERSION", RMS_Config.loadedConfigVersion, "CURRENT", RMS_Config.CONFIG_VERSION)
    local v

    -- core
    v = getXMLFloat(xmlFile, root .. ".BASE_SERVICE_WEAR")
    if v ~= nil then RMS_Config.CORE.BASE_SERVICE_WEAR = v end

    v = getXMLFloat(xmlFile, root .. ".BASE_SYSTEMS_WEAR")
    if v ~= nil then RMS_Config.CORE.BASE_SYSTEMS_WEAR = v end

    v = getXMLBool(xmlFile, root .. ".GENERAL_WEAR_ENABLED")
    if v ~= nil then RMS_Config.CORE.GENERAL_WEAR_ENABLED = v end

    v = getXMLBool(xmlFile, root .. ".ENABLE_WARNING_MESSAGES")
    if v ~= nil then RMS_Config.CORE.ENABLE_WARNING_MESSAGES = v end

    -- maintenance
    v = getXMLBool(xmlFile, root .. ".INSTANT_INSPECTION")
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_INSPECTION = v end

    v = getXMLBool(xmlFile, root .. ".INSTANT_MAINTENANCE_REPAIR")
    if v == nil then v = getXMLBool(xmlFile, root .. ".INSTANT_REPAIR") end
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR = v end

    v = getXMLBool(xmlFile, root .. ".INSTANT_BODYWORK")
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_BODYWORK = v end

    v = getXMLBool(xmlFile, root .. ".INSTANT_OVERHAUL")
    if v ~= nil then RMS_Config.MAINTENANCE.INSTANT_OVERHAUL = v end

    -- workshop
    v = getXMLBool(xmlFile, root .. ".DEALER_ALWAYS_AVAILABLE")
    if v ~= nil then
        RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE = v
    else
        v = getXMLBool(xmlFile, root .. ".ALWAYS_AVAILABLE")
        if v ~= nil then RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE = v end
    end

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

    -- thermal
    v = getXMLFloat(xmlFile, root .. ".TEMPERATURE_CHANGE_SPEED")
    if v ~= nil then RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED = math.clamp(v, 0.5, 2.0) end

    v = getXMLFloat(xmlFile, root .. ".TRANS_TEMPERATURE_CHANGE_MULTIPLIER")
    if v ~= nil then RMS_Config.THERMAL.TRANS_TEMPERATURE_CHANGE_MULTIPLIER = math.clamp(v, 0.5, 2.0) end

    v = getXMLFloat(xmlFile, root .. ".MAX_DIRT_INFLUENCE")
    if v ~= nil then RMS_Config.THERMAL.MAX_DIRT_INFLUENCE = math.clamp(v, 0.0, 1.0) end

    -- electrical
    v = getXMLFloat(xmlFile, root .. ".BATTERY_USABLE_CAPACITY_FACTOR")
    if v ~= nil then RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR = v end

    v = getXMLFloat(xmlFile, root .. ".ALT_MAX_OUTPUT")
    if v ~= nil then RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT = v end

    v = getXMLFloat(xmlFile, root .. ".IDLE_CURRENT_A")
    if v ~= nil then RMS_Config.ELECTRICAL.IDLE_CURRENT_A = v end

    -- drivetrain
    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_ENABLED")
    if v ~= nil then RMS_Config.DRIVETRAIN.ENABLED = v end

    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_ALLOW_AUTO_MODE")
    if v ~= nil then RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE = v end

    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_WINDUP_DAMAGE")
    if v ~= nil then RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED = v end


    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_PARKBRAKE_ENABLED")
    if v ~= nil then RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED = v end

    v = getXMLBool(xmlFile, root .. ".DRIVETRAIN_PARKBRAKE_AUTO")
    if v ~= nil then RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE = v end

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
        if Logging ~= nil and Logging.warning ~= nil then
            Logging.warning("RMS: settings file version %d is newer than supported %d", loadedVersion, currentVersion)
        end
        return
    end

    if loadedVersion < currentVersion then
        RMS_Config.migrateLoadedSettings(loadedVersion)
    end
end

---Migrates settings loaded from an older configuration file
-- @param integer loadedVersion version read from the file
function RMS_Config.migrateLoadedSettings(loadedVersion)
end
