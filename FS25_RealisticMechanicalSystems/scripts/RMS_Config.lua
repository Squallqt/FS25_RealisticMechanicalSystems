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

        -- low-speed band within the native idle to maximum rpm range
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
            HOT_OIL_THRESHOLD = 90,
            -- lifted mass ratio from which a bouncing implement shakes the lift in full
            VIB_FULL_LIFT_MASS_RATIO = 0.33,
            -- breakdown stage from which a clogged filter's bypass wears the circuits it feeds
            FILTER_BYPASS_STAGE = 2,
            FILTER_BYPASS_MULTIPLIER = 0.5
        },

        PTO_FACTOR_DATA = {
            SERVICE_EXPIRED_MULTIPLIER = 4.0,
            -- PTO torque share from which a sustained load strains the driveline
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
            -- engagement shock: rpm share it starts at, condition taken at full rpm, smallest implement
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
            -- a quarter of the chassis, the wiring riding on the frame
            VIB_FACTOR_MULTIPLIER = 9.0
        },

        CHASSIS_FACTOR_DATA = {
            CHASSIS_IDLING_MULTIPLIER = 0.5,
            LUBRICATION_FACTOR_MULTIPLIER = 5.0,
            VIB_FACTOR_THRESHOLD = 0.08,
            VIB_FACTOR_MAX_SIGNAL = 0.36,
            VIB_FACTOR_MULTIPLIER = 36.0,
            -- steering at rest: wear per lock a second on grip 1, fade speed, moving threshold, stall load
            STEER_LOAD_FACTOR_MULTIPLIER = 1.33,
            STEER_LOAD_SPEED_THRESHOLD = 4.0,
            STEER_LOAD_RATE_DEADZONE = 0.02,
            STEER_LOAD_AXLE_RATIO_MAX = 3.0,
            -- share of its play a full suspension stroke kicks a steered wheel by, and its full-kick speed
            STEER_PLAY_KICK_GAIN = 3.0,
            STEER_PLAY_FULL_SPEED = 30.0,
            -- seconds a rolling wheel takes to trail straight inside its play
            STEER_PLAY_RECENTER_TIME = 0.6,
            -- degrees before a steering stop within which a fault fades out
            STEER_STOP_BLEND = 4.0,
            -- play in degrees a worn chassis reaches without a declared breakdown
            STEER_GENERAL_WEAR_PLAY = 1.5,
            -- front end wobble: start play in degrees, speed band, frequency, share of the play
            STEER_SHIMMY_MIN_PLAY = 2.0,
            STEER_SHIMMY_SPEED_MIN = 25.0,
            STEER_SHIMMY_SPEED_PEAK = 35.0,
            STEER_SHIMMY_SPEED_MAX = 45.0,
            STEER_SHIMMY_FREQUENCY = 6.0,
            STEER_SHIMMY_SHARE = 0.4,
            -- wheel with a broken rod end: flutter in degrees, over the speed band in km/h it grows on
            STEER_FREE_FLUTTER_ANGLE = 12.0,
            STEER_FREE_FLUTTER_SPEED_MIN = 8.0,
            STEER_FREE_FLUTTER_SPEED_MAX = 25.0,
            -- play in degrees of an articulation whose linkage let go
            STEER_FREE_ARTICULATION_PLAY = 6.0,
            -- impact: km/h lost beyond the tyres' grip for a hit, condition per km/h lost and at most
            TERRAIN_IMPACT_MIN_SPEED_LOSS = 10.0,
            TERRAIN_IMPACT_DAMAGE_PER_KMH = 0.001,
            TERRAIN_IMPACT_MAX_DAMAGE = 0.05,
            -- tips: ms of shaking wear before its tip, ms a hit stays news
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


        -- engine power counting as turbocharged, in kw
        TURBO_MIN_POWER_KW = 56,

        BASE_BREAKDOWN_PROGRESS_TIME = 1 * 3600000,
        BREAKDOWN_PROBABILITIES = {
            STRESS_THRESHOLD = 0.5,
            MIN_FAILURE_DELAY_MINUTES = 30,
            MAX_FAILURE_DELAY_MINUTES = 5200,
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
        -- estimated complete jobs on the reference machine, access and testing included
        REPAIR_OPERATIONS = {
            ECU_MALFUNCTION = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            CORRODED_WIRING = {hours = 2, category = "diagnostic"},
            BATTERY_SULFATION = {hours = 0.5, category = "external"},
            GLOW_PLUG_FAILURE = {hours = 1.5, category = "mechanical"},
            ALTERNATOR_REGULATOR_FAILURE = {hours = 2, category = "mechanical"},
            INVERTER_MALFUNCTION = {hours = 4, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            DCDC_CONVERTER_FAILURE = {hours = 3, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            ONBOARD_CHARGER_FAILURE = {hours = 3, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            HV_INSULATION_LOSS = {hours = 4, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            ENGINE_JAM = {hours = 40, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            TURBOCHARGER_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            OIL_PUMP_MALFUNCTION = {hours = 8, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            VALVE_TRAIN_MALFUNCTION = {hours = 12, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            ELECTRIC_MOTOR_BEARING_WEAR = {hours = 8, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            ELECTRIC_MOTOR_WINDING_FAULT = {hours = 12, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            MOTOR_POSITION_SENSOR_FAULT = {hours = 3, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            MANUAL_TRANSMISSION_CLUTCH_WEAR = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = {hours = 18, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            POWERSHIFT_HYDRAULIC_PUMP_MALFUNCTION = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            CVT_CHAIN_WEAR = {hours = 24, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = {hours = 6, category = "transmission", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            TRANSMISSION_THERMOSTAT_MALFUNCTION = {hours = 2, category = "mechanical"},
            TRANSMISSION_OIL_LEAK = {hours = 10, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            CVT_ADDON_MALFUNCTION = {hours = 8, category = "transmission", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            REDUCER_GEAR_WEAR = {hours = 12, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            HYDRAULIC_PUMP_MALFUNCTION = {hours = 6, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            HYDRAULIC_CYLINDER_INTERNAL_LEAK = {hours = 4, category = "mechanical"},
            HYDRAULIC_HOSE_EXTERNAL_LEAK = {hours = 1, category = "external"},
            HYDRAULIC_FILTER_CLOGGING = {hours = 0.75, category = "external"},
            HYDRAULIC_OIL_COOLER_MALFUNCTION = {hours = 3, category = "mechanical"},
            HYDRAULIC_SPOOL_VALVE_MALFUNCTION = {hours = 5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PTO_DRIVE_COUPLING_WEAR = {hours = 10, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PTO_DRIVE_OUTPUT_BEARING_WEAR = {hours = 8, category = "transmission", mobileRequirement = "MOBILE_HEAVY_WORK"},
            PTO_ENGAGEMENT_CONTROL_MALFUNCTION = {hours = 3, category = "diagnostic", mobileRequirement = "MOBILE_DIAGNOSTIC"},
            BRAKE_MALFUNCTION = {hours = 6, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            BEARING_WEAR = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            STEERING_LINKAGE_WEAR = {hours = 2, category = "external"},
            TRACK_TENSIONER_MALFUNCTION = {hours = 5, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            THERMOSTAT_MALFUNCTION = {hours = 2, category = "mechanical"},
            COOLANT_LEAK = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FAN_CLUTCH_FAILURE = {hours = 3, category = "mechanical"},
            COOLANT_PUMP_FAILURE = {hours = 3, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FUEL_PUMP_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FUEL_INJECTOR_MALFUNCTION = {hours = 4, category = "mechanical", mobileRequirement = "MOBILE_HEAVY_WORK"},
            FUEL_FILTER_CLOGGING = {hours = 0.75, category = "external"},
            FUEL_LINE_AIR_LEAK = {hours = 1.5, category = "external"},
            TRACTION_BATTERY_CELL_FAULT = {hours = 12, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
            HV_CONTACTOR_FAILURE = {hours = 4, category = "highVoltage", mobileRequirement = "MOBILE_HIGH_VOLTAGE"},
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
        -- repair categories only a diagnostic tool reads
        INSPECTION_TOOL_CATEGORIES = { diagnostic = true, highVoltage = true },

        MAINTENANCE_PREVENTIVE_STRESS_REMOVE_MULTIPLIER = 0.6,

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
        -- real dealer prices sized on engine power, scaled by the economic difficulty
        REFERENCE_POWER = 160,
        -- a dealer's hourly rate in euros
        LABOUR_RATE = 90,
        -- how labour and parts follow engine power, from filter kits of 75 to 430 hp
        LABOUR_POWER_EXPONENT = 0.4,
        PARTS_POWER_EXPONENT = 0.6,
        -- labour, filters and parts of a road vehicle against a machine of the same power
        PROFILE_PRICE_FACTORS = {
            ROAD_LIGHT = { labour = 0.3,  filters = 0.2, parts = 0.5  },
            ROAD_HEAVY = { labour = 0.55, filters = 0.2, parts = 0.75 },
        },
        -- dealer maintenance of the reference machine: labour hours and filters in euros
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
        -- reference machine value the repair percentages and overhauls apply to
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
    -- common thermal rates in C/s and cooling in 1/s, one approximation for every model
    THERMAL = {
        TAU = 5000,
        PID_TARGET_TEMP = 90,
        TELLTALE = { WARNING = 99, CRITICAL = 110 },
        -- ECU diesel thresholds anchored on documented Deere alerts
        ENGINE_PROTECTION = {
            START_TEMP = 110,
            SEVERE_TEMP = 115,
            RELEASE_TEMP = 107,
            SEVERE_RELEASE_TEMP = 112,
        },
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
        -- dust left in a blown out filter at the cleaning threshold, the filter then due
        AIR_FILTER_REPLACEMENT_RESIDUE = 0.35,
        -- fuel and hydraulic filters: one service interval brings them to 1, each threshold a stage
        FILTER_STAGE_THRESHOLDS = { 1.0, 4 / 3, 5 / 3, 2.0 },
        -- a tank run on its reserve sends water and sediment to the fuel filter
        FUEL_FILTER_LOW_FUEL_MULTIPLIER = 3.0,
        -- working hydraulics send the filter what the pump and the cylinders wear off
        HYDRAULIC_FILTER_ACTIVE_MULTIPLIER = 2.0,
        -- length of sounds/inspection.ogg at pitch 1
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

        -- oil a healthy engine burns per interval: 0.09 g/kWh, a fifth of a 160 hp sump
        ENGINE_OIL_CONSUMPTION_PER_INTERVAL = 0.20,
        -- extra burn of a worn engine: 0.3 % of its fuel, one and a half sumps per interval
        ENGINE_OIL_WEAR_CONSUMPTION = 6.5,
        -- share of the consumption that follows the motor load
        ENGINE_OIL_LOAD_SHARE = 1.5,

        -- minimum mark of the gauge: 2.1 of the 14.2 L of a Cummins 6B 5.9 lie between the marks
        LEVEL_MIN_MARK = 0.85,
        -- levels the inspection reports under the mark
        LEVEL_LOW = 0.70,
        LEVEL_VERY_LOW = 0.50,
        LEVEL_CRITICALLY_LOW = 0.30,
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
        PARKBRAKE_AUTO_MIN_YEAR = 2010,
        PARKBRAKE_AUTO_STANDSTILL_MS = 45000,
        PARKBRAKE_LEVER_HOLD = 0.5,
        PARKBRAKE_AIR_HOLD = 1.0,
        PARKBRAKE_ROLLING_RESISTANCE = 0.03, -- brake pedal the game itself keeps on a vehicle out of gear
        PARKBRAKE_DRAG_WEAR_MULTIPLIER = 5.0 -- as much as a chassis run without grease
    },

    -- exhaust smoke colour and opacity
    EXHAUST = {
        ENABLED = true,

        -- smoke tints: black soot, blue oil, white fuel, off white water, colourless clean gas
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
            -- neighbours overlapping any point of the plume, and the rate bounds in puffs a second
            OVERLAP_TARGET = 5,
            RATE_MIN = 8,
            RATE_MAX = 720,
            -- most halvings the puffs retire in once they overlap more than needed
            THIN_LEVEL_MAX = 6,
            -- exit speed in m/s: cranking floor, full flow speed, sideways share of each puff
            EXIT_SPEED_MIN = 2.0,
            EXIT_SPEED_FULL = 30.0,
            SPREAD_SHARE = 0.02,
            -- tailpipe diameter in metres per square root of kW, within bounds
            PIPE_DIAMETER_PER_SQRT_KW = 0.009,
            PIPE_DIAMETER_MIN = 0.06,
            PIPE_DIAMETER_MAX = 0.16,
            -- sprite width over gas width, visible share of the sprite, widest sprite downstream
            SPRITE_GAS_RATIO = 1.65,
            RADIUS_SHARE = 0.45,
            SIZE_MAX = 8.0,
            -- width the gas gains per metre through the air, and per metre of crosswind taken in
            JET_SPREAD = 0.22,
            JET_CROSS_SPREAD = 0.10,
            -- step in ms of the jet profile the spacing and the sprite growth are read on
            JET_PROFILE_STEP_MS = 50,
            -- growth the eddies of the air add in m/s, a floor and the crosswind mixing it
            GROWTH_BASE = 0.18,
            GROWTH_PER_WIND = 0.15,
            -- share of its life a sprite growth is fitted over, and its bounds in ms
            GROWTH_FIT_SHARE = 0.35,
            GROWTH_FIT_MIN_MS = 400,
            GROWTH_FIT_LEVEL_MIN_MS = 20,
            GROWTH_FIT_MAX_MS = 4000,
            -- speed the rising plume carries its puffs apart at even in still air, in m/s
            RISE_SPEED = 0.40,
            -- width the condensed water shows the model vapour at, a few decimetres out
            REFERENCE_SIZE = 0.50,
            -- life bounds in ms, and the plume optical depth under which it no longer shows
            LIFE_MIN = 800,
            LIFE_MAX = 8000,
            TAU_VISIBLE = 0.02,
            -- how much of the sprite area the smoke texture covers, tuned in game
            SPRITE_ALPHA_GAIN = 1.60,
            -- relative change under which a puff is not rewritten, so a faint puff among many still thins
            ALPHA_EPSILON = 0.03,
            -- fade out in ms of the puffs reaching the end of the plume, the asset having none
            FADE_OUT_MS = 300,
            -- drag toward the surrounding air per second, on top of the entrainment
            BASE_DAMPING = 1.20,
            -- crosswind in m/s from which that drag applies in full, and the share left in still air
            DAMPING_CROSS_SPEED = 2.0,
            DAMPING_FLOOR_SHARE = 0.30,
            -- speed share a puff keeps along a surface, and the air flow share a surface turns aside
            SURFACE_SPREAD = 0.06,
            SURFACE_FLOW_SHARE = 0.85,
            -- speed a puff that overlaps a surface eases off it at, in m/s, instead of jumping clear in one step
            SURFACE_PUSH_SPEED = 1.5,
            -- a puff wider than this also looks straight above itself for a roof, in metres
            ROOF_PROBE_MIN_RADIUS = 0.30,
            -- wind share under a roof, its reach in metres, check interval in ms and response
            SHELTER_WIND_SHARE = 0.15,
            SHELTER_RADIUS = 8.0,
            SHELTER_CHECK_MS = 200,
            SHELTER_TAU = 400,
            -- lee of an obstacle upwind: search range and height, least wind, wind share and recovery
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

        -- exhaust gas temperature rise in kelvin at idle and full load, cold share, mixing exponents
        EGT = {
            RISE_IDLE_K = 120,
            RISE_FULL_K = 430,
            COLD_FACTOR = 0.45,
            DILUTION_EXPONENT = 1.30
        },

        -- eddies of the air in m/s, with the wavelength, frequency and weight of each octave
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

        -- condensing combustion water: ambient range, depth, humidity, fuel, cold engine, evaporation
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

        -- unburnt channel eras, injection and glow plugs improving far less than particulate control
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

    -- 12 and 24 V circuits, each value sourced in docs/RMS_ELECTRICAL_REFERENCES.md
    ELECTRICAL = {
        -- sizing law measured on tractors: value at 100 hp in 2000, power exponent, factor per decade
        RATING = {
            POWER_RANGE_HP = { 20, 705 },
            YEAR_RANGE = { 1970, 2026 },
            ALTERNATOR_A = { base = 80.7, powerExponent = 0.53, decadeFactor = 1.27 },
            BATTERY_AH = { base = 124.6, powerExponent = 0.60, decadeFactor = 0.93 },
            STARTER_KW = { base = 2.93, powerExponent = 0.44, decadeFactor = 1 },
            -- a machine carries parts of a catalogue: alternators are sold by 5 A, batteries read by 10 Ah
            ALTERNATOR_STEP_A = 5,
            BATTERY_STEP_AH = 10,
            TELEHANDLER_ALTERNATOR_A = 90,
            -- these run 24 V on two 12 V batteries in series, of a capacity that does not follow their power
            SYSTEM_24V_FAMILIES = { FORESTRY = true, ROAD_HEAVY = true },
            WHEEL_LOADER_24V_ABOVE_HP = 110,
            BATTERY_24V_AH = 180,
            -- the diesel pickup published in full stands for every light road vehicle
            ROAD_LIGHT = { alternatorA = 175, batteryCapacityAh = 156, starterKw = 4.2 }
        },
        -- resting voltage of one 12 V battery by state of charge; every voltage below is that of one battery
        OCV_CURVE = { { 0, 11.7 }, { 0.25, 12.0 }, { 0.5, 12.2 }, { 0.75, 12.4 }, { 1, 12.6 } },
        REGULATED_VOLTAGE_V = 14.0,
        MIN_CRANKING_VOLTAGE_V = 7.2,
        -- ohms of a battery of one amp hour, by temperature
        INTERNAL_RESISTANCE_CURVE = { { -18, 0.51 }, { -10, 0.49 }, { 0, 0.46 }, { 25, 0.30 } },
        -- resistance of an empty battery against a full one, an estimate
        EMPTY_RESISTANCE_FACTOR = 2.0,
        -- starter speed share on a full battery by engine temperature: 250 rpm at 22 C, 150 at -19
        CRANKING_DRAG_CURVE = { { -19, 0.65 }, { 22, 1 } },
        -- share of that reference speed a diesel needs to fire: 100 of 250 rpm (Caterpillar)
        FIRING_CRANKING_SPEED = 0.4,
        -- share of the charge the cold keeps out of reach, by temperature
        INACCESSIBLE_CHARGE_CURVE = { { -18, 0.54 }, { -12, 0.44 }, { -7, 0.34 }, { -1, 0.27 }, { 2, 0.21 }, { 10, 0.12 }, { 27, 0 } },
        -- charge a battery takes, in capacities per hour, below then above the topping level
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
        -- standard work lamps: by era, then by power from 2012 on; twice as many on a combine or a forage harvester
        WORK_LAMPS_BEFORE_1990 = 2,
        WORK_LAMPS_BEFORE_2012 = 6,
        WORK_LAMPS_BY_POWER = { { 100, 4 }, { 170, 6 }, { 300, 8 }, { 400, 10 }, { math.huge, 12 } },
        WORK_LAMPS_HARVESTER_FACTOR = 2,
        WORK_LAMP_HALOGEN_W = 55,
        WORK_LAMP_LED_W = 45,
        WORK_LAMP_LED_YEAR = 2014,
        -- starter current for one kilowatt, by temperature
        STARTER_CURRENT_CURVE = { { -20, 165 }, { 0, 145 } },
        GLOW_PLUG_A = 12,
        GLOW_PLUGS_BY_POWER = { { 130, 4 }, { math.huge, 6 } },
        STANDBY_A = 0.05,
        -- resting draw a circuit is held faulty from, a failing regulator or wiring leaking 1 to 8 times it
        LEAKAGE_FAULT_A = 0.1,
        SELF_DISCHARGE_PER_MONTH = 0.05,
        SELF_DISCHARGE_REFERENCE_TEMP_C = 25,
        SELF_DISCHARGE_DOUBLING_C = 10,
        MONTH_HOURS = 730.5,
        -- drop a healthy circuit is allowed under the starter, positive and ground sides together
        CIRCUIT_ADMISSIBLE_DROP_V = 0.7,
        -- 2 AWG copper cables of 20 feet, out and back
        JUMPER_CABLE_RESISTANCE_OHM = 0.00625,
        VOLTAGE_SAG_V = 12.0,
        VOLTAGE_SAG_DELAY_MS = 2000,
        -- needle inertia of the voltmeter
        SYSTEM_VOLTAGE_TAU_MS = 250
    },

    -- electric vehicles: motor and traction battery
    ELECTRIC_DRIVE = {
        -- a motor at rest does not turn, sustained overload heats its windings
        MOTOR_STANDSTILL_MULTIPLIER = 0.1,
        MOTOR_OVERLOADED_THRESHOLD = 0.90,
        MOTOR_OVERLOADED_MAX_EFFECT = 1.05,
        MOTOR_OVERLOADED_MULTIPLIER = 1.0,
        MOTOR_OVERHEAT_MULTIPLIER = 50.0,
        -- emptying the pack under load, a sustained high draw and heat age the cells
        DEEP_DISCHARGE_THRESHOLD = 0.15,
        DEEP_DISCHARGE_MULTIPLIER = 3.0,
        HIGH_DRAW_THRESHOLD = 0.85,
        HIGH_DRAW_MULTIPLIER = 1.0,
        BATTERY_HEAT_THRESHOLD = 40,
        BATTERY_HEAT_FULL_EFFECT = 60,
        BATTERY_HEAT_MULTIPLIER = 10.0,

        -- representative motor and inverter temperature limits
        THERMAL = {
            PID_TARGET_TEMP = 60,
            OVERHEAT_THRESHOLD = 70,
            OVERHEAT_FULL_EFFECT = 100,
            TELLTALE = { WARNING = 75, CRITICAL = 85 }
        },
        -- temperatures each cold stage of the pack starts under
        BATTERY_COLD_STAGES = { 10, 0, -10, -20 },

        -- share of its capacity a worn out pack has lost
        BATTERY_CAPACITY_FADE = 0.20,
        -- share of a station's power the pack takes at each temperature, cold cells accepting little
        CHARGE_ACCEPTANCE_CURVE = { { -10, 0.2 }, { 0, 0.5 }, { 10, 1.0 } },
        -- energy a slowed charge hands over at once, well above the amount a station takes for a full battery
        CHARGE_SLICE = 0.001
    },

    -- qualitative calibration, model entries first, unknown brands on the fair baseline
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

    -- one 500 hour reference keeps the documented differences between programmes
    SERVICE_REFERENCE_HOURS = 500,
    -- ratings follow actual labour, not brand prestige
    SERVICE_ACCESS_PROFILES = {
        SIMPLE = {label = "rms_service_access_easy", transmission = 0.9},
        STANDARD = {label = "rms_service_access_average"},
        COMPLEX = {label = "rms_service_access_demanding", transmission = 1.25, diagnostic = 1.25}
    },
    SERVICE_ACCESS_OVERRIDES = {
        -- accessible routine service points, internal gearbox work apart
        ["data/vehicles/deutzfahr/series6c/series6c.xml"] = {maintenance = 0.9},
        ["data/vehicles/zetor/proximahs120/proximahs120.xml"] = {profile = "SIMPLE", maintenance = 0.9}
    },
    SERVICE_PROGRAM = {
        engine = { hours = 500, months = 12 },
        transmission = { hours = 1000, months = 24 },
        hydraulic = { hours = 1000, months = 24 },
        coolant = { hours = 2000, months = 24 }
    },
    SERVICE_PROGRAMS = {
        -- Deutz-Fahr 6C brochure p.43, the FS25 RVshift models having the Deutz 3.6 engine
        ["data/vehicles/deutzfahr/series6c/series6c.xml"] = {
            engine = { hours = 500, months = 12 },
            transmission = { hours = 1000, months = 12 },
            hydraulic = { hours = 1000, months = 12 }
        },
        -- Stage V T Series: 600 hour service and yearly minimum, other circuits estimated
        ["data/vehicles/valtra/tseries/tseries.xml"] = {
            engine = { hours = 600, months = 12 }
        },
        -- Stage V Puma family, the 260 approximated on it
        ["data/vehicles/caseih/puma/puma.xml"] = {
            engine = { hours = 750, months = 18, estimated = true },
            transmission = { hours = 1500, estimated = true },
            hydraulic = { hours = 1500, estimated = true }
        }
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
RMS_Config.legacySavegameFile = "advancedDamageSystem.xml"

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

    local isLegacyFile = false
    if not fileExists(xmlFileName) then
        xmlFileName = savegameFolderPath .. "/" .. RMS_Config.legacySavegameFile
        isLegacyFile = fileExists(xmlFileName)
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
