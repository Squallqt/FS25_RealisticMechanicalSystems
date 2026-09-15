# FS25_RealisticMechanicalSystems

In-depth vehicle wear, failure, diagnostics, maintenance, and repair system for Farming Simulator 25.

[![Version](https://img.shields.io/badge/version-0.10.0.0-blue.svg)](#)
[![FS25](https://img.shields.io/badge/FS25-compatible-green.svg)](https://farming-simulator.com/)
![Multiplayer](https://img.shields.io/badge/multiplayer-supported-success.svg)
![Languages](https://img.shields.io/badge/languages-27-blue.svg)
[![License](https://img.shields.io/badge/license-GPL--3.0-yellow.svg)](LICENSE)

Every machine is built from up to 8 individual systems, each with its own condition, its own wear factors, and its own way of failing. Service on schedule, work the machine within its limits, and watch for the early symptoms: the cheapest repair is always the one you catch first.

Singleplayer, multiplayer, and dedicated server.

Electric vehicles are not supported yet.

> **Note:** This repository is an independently maintained fork of Advanced Damage System by id577, developed by Squallqt since 30 June 2026. The gameplay model and the documentation have been substantially reworked since then; the original credits and provenance are preserved unchanged in [NOTICE.md](NOTICE.md).

## Quick Start

Three rules are enough to play without constant breakdowns:

1. **Follow the service interval.** Around `5 operating hours` on average by default. Check it in the workshop, in the vehicle info panel, or in the fleet menu (`P` key), then run `Maintenance`.
2. **Prepare your machines daily.** Hold `R` near a vehicle for a pre-shift check, clean it with the `Air Blower`, and grease what needs greasing with the `Grease Gun`.
3. **Do not abuse your equipment.** If it would damage a real machine, it damages this one: overloading, overheating, cold-engine work, wheel slip in mud, oversized implements, speed over rough ground.

## Core Mechanics

Every system tracks three values.

- **Condition**: health and remaining service life. It sets how much abuse a system tolerates before failures become likely. It drops about `1%` per operating hour under normal use, faster under harsh use, and very slowly on a vehicle stored outdoors. Restored by `Overhaul`.
- **Stress**: accumulated misuse. It does not build during normal operation, only through overload, overheating, cold running, wheel slip, and system-specific mistakes. Breakdown probability rises as Stress approaches that system's current Condition. Reduced by preventive maintenance, by repairs, and automatically once a breakdown occurs.
- **Service**: the state of oils, filters, and fluids. It falls with operating hours, and a low level accelerates Condition loss across every system, the engine most of all. Restored by `Maintenance`.

Inspection reports give an approximate status (`OPTIMAL`, `REQUIRED`, `OVERDUE`). Exact percentages require a full defectoscopy, which is slow and expensive, and rarely worth it: following the recommended interval works better than measuring.

## Wear Factors

Normal wear depends on system activity. Hydraulics and PTO wear only while active; the other enabled systems retain their idling and downtime wear. Overdue service adds wear while the affected system operates, and poor-quality consumables increase overall Condition wear.

| System | Wear factors |
| --- | --- |
| **Engine** | Load above `85%`; air filter clogged past `50%`; cold running below `50C` at high RPM load; overheating above `95C` under load; oil level under `50%` |
| **Transmission** | Sustained pull above `85%` load, with an accumulation window scaling from `30` to `90` seconds; lugging (high load, low RPM); wheel slip above `5%` under `20 km/h`; heavy trailer below `10 hp/t` (`6 hp/t` for trucks); a load held on oil below `45C`; on CVT, overheating above `100C`; oil level under `50%` |
| **Hydraulics** | Pump running whenever the engine runs; lifted implement mass on the linkage; vibration while carrying an implement over rough ground; qualified hydraulic movement; cold oil proxy below `30C`; hot oil proxy above `90C`; fluid level under `50%` |
| **Cooling** | Thermostat past `95%` open while the engine is more than `3C` over its target; engine above `95C`; cold shock below `50C` at high RPM load |
| **Electrical** | Lights on; rain, snow, or hail on an outdoor vehicle; starter cranking; engine above `95C`; vibration over rough ground at speed |
| **Chassis** | Poor lubrication on machines that require greasing; vibration over rough ground at speed; steering under `4 km/h`, scaled by the steered angle and by the load the steered axle really carries; braking above `2 km/h` while towing |
| **Fuel** | Fuel below `20%` under load; fuel colder than `20C` above `50%` load; idling past `60` seconds; fuel consumption above `80%` of the configured maximum |
| **PTO** | Active drive; continuous native PTO utilization above `55%`, reaching its full overload factor at `90%`; unique engagement cycles are recorded for fault selection without instant engagement damage |

AI workers wear a machine exactly like a player. They are protected by behaviour instead: the helper slows down on overload or overheating, never stalls, and is never blocked by a hard start.

## Breakdowns

Breakdown probability depends entirely on how close a system's Stress is to its Condition. Condition also sets the chance of a **critical** failure, one that appears straight at stage 4 and skips the rest. The type is not random: the mod tracks which wear factors have been active most and picks the failure that history makes most likely.

Most breakdowns run through four stages, **Minor**, **Moderate**, **Major**, and **Critical**, each costing more to repair than the last. Progression is context-dependent; some faults only worsen while the machine performs the work that causes them. Modern vehicles get dashboard indicators from stage 2, but stage 1 is silent and only shows itself through symptoms: fluctuating RPM, coloured exhaust smoke, knocking, squealing. Catching one there costs almost nothing.

Beyond individual failures, low Condition triggers a permanent **General Wear and Tear** effect: an old machine loses engine power, transmission bite, battery performance, and cooling efficiency even with nothing formally broken.

### Reading the smoke

The exhaust plume is a real diagnostic channel, not decoration. Its colour comes from three mixed sources, its density from how bad things are.

| Colour | What it means | Usual causes |
| --- | --- | --- |
| Black | Too much fuel for the available air | A hard pickup before the turbocharger catches up, lugging at low revs, overload, clogged air filter, worn turbocharger, failing injectors, ECU fault |
| Blue | The engine is burning its own oil | Worn engine at low Condition, leaking turbocharger seals, valve train wear |
| White | Fuel leaving the engine unburnt | Cold engine, failed glow plugs, failing injection or a starving fuel system |

Production year matters as much as condition. With the same fault, an older machine always smokes more, and a recent one running AdBlue shows almost nothing until something actually breaks. A cold start still shows on a recent machine, briefly, because high injection pressure and glow plugs improved far less than particulate control did.

The plume is drawn as real smoke particles, layered from a tight jet at the pipe to a slow trail behind. A clean plume dissipates at once; a loaded one hangs and takes seconds to clear. It follows the gas the engine actually moves, so it swells under boost and shrinks when the engine is coasting. On a turbocharged machine, black smoke appears whenever the fuel outruns the air: for a moment on a hard pickup while the turbocharger spools up, and for as long as it lasts on an engine held at full load down at low revs. A naturally aspirated engine never shows either, since without boost its air flow follows the engine speed alone.

Leaving a diesel idling also leaves its mark. Past a long idle under `30%` load, unburnt carbon builds up and darkens the plume. The deposit survives an engine stop and a save, then burns off only once the engine is warm and working under load.

<details>
<summary><strong>Full breakdown list</strong></summary>

| Breakdown | Applies to | Critical effect |
| --- | --- | --- |
| ECU Malfunction | Non-electric, `2000+` | Engine cannot be controlled and will not start |
| Corroded Wiring | `2000+` with lights | Lights dead, engine start impossible |
| Battery Sulfation | All | Cranking too weak to start reliably |
| Glow Plug Failure | Diesel | No start when preheating is required |
| Alternator Regulator Failure | All | No charging, battery reserve only |
| Turbocharger Wear | Engines from `56 kW` (`75 hp`) | Most engine power lost, further damage likely |
| Oil Pump Malfunction | All non-electric | Oil circulation lost, running and starting unsafe |
| Valve Train Malfunction | All non-electric | Engine cannot run correctly, may not start |
| Manual Clutch Wear | Manual transmissions | Clutch burnout, vehicle cannot move |
| Synchronizer Malfunction | Manual and synchro-shift | Shifting impossible |
| Powershift Pump Malfunction | Powershift | Transmission stuck in neutral |
| CVT Chain Wear | CVT | Movement no longer reliable |
| CVT Control Valve Malfunction | CVT | Severely restricted emergency mode |
| CVT Addon Malfunction | Vehicles using CVT Addon | Complete CVT failure, vehicle cannot move |
| Transmission Thermostat Malfunction | CVT | Thermostat stuck at one opening, the oil either overheats or never warms up |
| Transmission Oil Leak | All non-electric | Too little oil left to run the transmission safely |
| Hydraulic Pump Malfunction | Vehicles with qualified hydraulic functions | Hydraulic system inoperable |
| Hydraulic Cylinder Internal Leak | Vehicles with a qualified hydraulic lift | Raised loads drop rapidly |
| Hydraulic Hose External Leak | Vehicles with declared hydraulic connections | Hydraulic performance strongly reduced |
| Hydraulic Filter Clogging | Vehicles with qualified hydraulic functions | Hydraulic functions barely respond |
| Hydraulic Oil Cooler Malfunction | Vehicles with qualified hydraulic functions | Active hydraulic work overheats the accepted oil-temperature proxy |
| Hydraulic Control Valve Malfunction | Vehicles with a qualified controllable hydraulic target | One qualified hydraulic function becomes erratic or blocked |
| PTO Drive Coupling Wear | Vehicles with a physical PTO output | PTO power can no longer be transmitted |
| PTO Drive Output Bearing Wear | Vehicles with a physical PTO output | PTO operation becomes impossible |
| PTO Engagement Control Malfunction | Vehicles with a physical PTO output | PTO engagement becomes unreliable, then impossible |
| Brake Malfunction | Wheeled | Braking impossible |
| Bearing Wear | Wheeled | Wheel rotation blocked |
| Steering Linkage Wear | Wheeled without tracks | Directional control unsafe |
| Track Tensioner Malfunction | Tracked | Running gear can seize |
| Thermostat Malfunction | All non-electric | Coolant circulation disrupted, overheating unavoidable |
| Coolant Leak | All non-electric | Safe engine temperature unreachable |
| Fan Clutch Failure | All non-electric | Cooling airflow insufficient |
| Fuel Pump Malfunction | All non-electric | No fuel delivered to the engine |
| Fuel Injector Malfunction | All non-electric | Engine will not run correctly, may not start |
| Fuel Filter Clogging | All non-electric | Fuel flow insufficient to run |
| Fuel Line Air Leak | All non-electric | Fuel supply cannot be maintained |

</details>

## Workshop

Four procedures, each with options that change duration, cost, and quality. All of them take real time, and the workshop closes overnight: work in progress resumes the next opening. Planning when a machine goes in matters as much as paying for it.

- **Inspection**: `Visual` is quick but can miss things, `Standard` detects faults and reports condition, `Complete Defectoscopy` finds hidden faults and defective parts and gives exact values.
- **Maintenance**: replaces oils, filters, and fluids, and restores Service. `Minimal` is cheap and partial, `Standard` follows manufacturer spec, `Extended` restores above normal, `Preventive` also strips Stress from the worst systems. The cost is **fixed**, so servicing at `90%` costs the same as at `10%`.
- **Repair**: `Quick Fix` suppresses the symptoms without fixing the fault, which returns. `Standard` replaces the failed part and cuts Stress. `Advanced` replaces everything around it and zeroes Stress.
- **Top up**: fills whatever fluid the machine is missing, for the price of the fluids alone. Quick, and the button disappears once everything is full.
- **Overhaul**: restores Condition on one system or all of them, clears breakdowns, and includes maintenance unless partial. `Partial`, `Standard`, and `Full` differ in scope and price. Paintwork can be renewed for a fee. It never restores a flat `100%`: the result depends on maintainability, on how many overhauls the machine already had, and on chance.

Maintenance and repair let you pick part quality between `Used`, `Aftermarket`, `OEM`, and `Premium`. Cheaper parts are more often defective: on maintenance they shorten the interval and accelerate wear, on repair they bring the same fault back. Complete Defectoscopy detects them.

## Pre-Shift Care

- **Pre-shift check**: hold `R` near a vehicle for a go or no go verdict, the machine and its next service, the four fluid levels, radiator and air filter fouling, and reveal faults a real visual check would catch. Takes seconds, works anywhere.
- **Fluids**: engine oil, coolant, transmission oil and hydraulic fluid each have a level, read against the minimum mark of their gauge. Engine oil is burnt off with the work done, faster under load and much faster as the engine wears, so a healthy engine always reaches its next service above the mark whatever interval you set while a tired one asks to be topped up; the other three only drop through a leak. Under the mark the machine only asks for a top up and still works normally; it is under `50%` that a machine short of coolant or transmission oil runs hot, and one short of engine oil or hydraulic fluid wears faster. The workshop `Top up` service fills what is missing for the price of the fluids, maintenance and overhaul replace everything, and a repair puts back what the fault it fixed had let out.
- **Wrong fluid**: manually transferring an incompatible product contaminates only the selected circuit. Depending on the proportion in the mixture, system wear can rise to three times its normal rate, heat can increase, and contaminated hydraulic fluid can slow hydraulic functions by up to `25%`. The transfer requires explicit confirmation, and only a complete fluid replacement clears the contamination. Workshop procedures only reserve compatible products.
- **Air Blower**: clears dust from the cooling pack and the air filter. A clean radiator will not overheat. Blowing an air filter out only recovers part of it, since what is embedded in the media stays until maintenance replaces it, and washing the machine never touches it.
- **Grease Gun**: restores lubrication on machines that need it, harvesters above all. Lubrication drops `10%` per period only if the machine was neither operated, greased, nor serviced during it; inspection alone does not count.
- **Aiming a hand tool**: point it directly at the machine within `5 m`.

## Reliability and Maintainability

Every brand carries two ratings based on its real-world reputation, both shown in the shop.

- **Reliability** slows Condition loss, lowers base breakdown probability, and lengthens service intervals. Premium European and American brands generally rate higher than budget or older Eastern European ones.
- **Maintainability** cuts the money and time of every workshop operation and improves how much an overhaul recovers. Simple older machines usually beat modern electronics-heavy ones.

Vehicles also age: production year drives thermostat behaviour, overheat protection, how much the machine smokes, and which breakdowns can occur at all.

Three settings cover the exhaust. `Exhaust Smoke` turns the model on or off and `Smoke Intensity` scales opacity from `100%` to `300%`, neither of them changing the calculated causes or colours; both belong to the server. `Plume Detail` belongs to each player instead: it sets how many layers of smoke their own machine draws, down to none, and never affects anyone else. It can only reduce what the server allows. Turning the model off restores the vehicle's native exhaust.

## Buying Used

A used machine arrives with the wear its hours have earned, and it may carry a fault nobody declared. Nothing shows at the sale.

The hours set the odds, the brand shifts them:

| Hours on the clock | Reliable brand | Budget brand |
| --- | --- | --- |
| 10 h | 7% | 11% |
| 25 h | 18% | 28% |
| 45 h | 32% | 51% |

Run an `Inspection` before the machine sees any work. `Standard` finds most of it, `Complete Defectoscopy` finds all of it along with the exact condition of every system. Skipping that step is how a bargain becomes a breakdown in the middle of a field.

## Thermal Model

Engine temperature is computed from load, ambient temperature, dirt on the radiator, airflow from speed, and thermostat state, and it feeds directly into wear and failure risk.

- **Engine thermostat behaviour follows production year.** Older machines have inert mechanical thermostats with real stiction; modern ones use fast PID control that adapts quickly to load.
- **Overheat protection is staged from `2000` onwards**: power is progressively limited, then the engine can shut down. Older vehicles have no such protection and can suffer a hard failure instead.
- **Warm-up is mandatory.** Cold oil only aggravates wear when the driveline is genuinely transmitting a heavy load. Idling and power used solely by an external consumer do not trigger cold-transmission wear.
- **Transmission oil is not held at a target temperature.** Like the real machines, its thermostat only decides whether the oil goes through the oil cooler or around it: around it while the oil is cold, through it as the oil warms. The temperature then floats with the job instead of holding one value.
- **A low fluid level costs cooling.** The minimum mark only asks for a top up, nothing changes there. Under `50%` the coolant carries less heat away and the transmission cooler loses capacity with the oil, down to `15%` on an empty circuit.
- **CVT machines run a separate transmission model** driven by the pump, the power take-off, transmission load, the hydrostatic ratio, wheel slip and acceleration. Slow high-stress work and jerky driving can cook a CVT while the engine still reads normal.
- **Heat follows real simulation time.** Engine and transmission temperatures are unaffected by the game time scale, cool independently after shutdown, and are preserved by savegames and multiplayer synchronization. Time spent outside the game is not simulated.

## Electrical System

The battery is a real model, not a switch: capacity falls in the cold, internal resistance rises with cold and age, and charge acceptance drops with low temperature, high state of charge, and poor health. A weak battery does not merely hold less; it also charges worse, sags harder, and cranks poorly.

The alternator output follows engine RPM, current load, and its own health. When consumers demand more than it delivers, voltage sags and the battery drains. Battery temperature is simulated on its own, driven by ambient air, engine bay heat, and self-heating from current.

If a battery is too flat to start, jumper cables link both vehicles into a shared circuit so the donor can support cranking or charge the receiver.

Diesel preheating starts automatically below `25 C`. It remains short in mild weather and lengthens progressively as the engine gets colder. At `5 C` and above, failed glow plugs can make the start rough but do not block it solely because of preheating; below that point, their condition becomes start-critical.

## Installation

1. Place the mod ZIP file into your FS25 `mods/` directory (do not extract).
2. Activate the mod in mod selection.
3. Access RMS from the fleet menu (`P` key), the in-game settings, and workshop interactions.

> **Important:** Do not run RMS and Advanced Damage System together. RMS steps aside when it finds ADS and leaves it in charge, so nothing runs twice. Removing ADS is enough: RMS then picks up the condition, the service history and the settings of your fleet from the savegame.

## Usage

### Running a service

1. Drive the vehicle to a workshop, or use a mobile workshop.
2. Pick `Inspection` first if you are unsure what is wrong, then `Maintenance`, `Repair`, or `Overhaul`.
3. Choose the scope and part quality; both change price and duration.
4. Read the report afterwards. The maintenance log keeps every past procedure.

### Reading the warning signs

1. Watch the dashboard indicators, which light from stage 2 on modern vehicles.
2. Listen for knocking, whistling, and grinding, and read the exhaust: black means the engine is choking on fuel it cannot burn, blue means it is burning oil, white means fuel is leaving the engine unburnt. Stage 1 is otherwise silent.
3. Run a pre-shift check when something feels off, then a workshop inspection if it does not clear.
4. Repair early. A stage 1 fault costs a fraction of a critical one.

## Console Commands

For testing and debugging. Most require you to be inside a vehicle that supports the mod. Typed on a client, they are relayed to the server.

| Command | Description |
| --- | --- |
| `rms_debug` | Toggles debug mode |
| `rms_listBreakdowns` | Lists every breakdown ID in the registry |
| `rms_addBreakdown [id] [stage]` | Adds a breakdown to the current vehicle |
| `rms_removeBreakdown [id]` | Removes one breakdown, or all of them without an ID |
| `rms_advanceBreakdown [id]` | Advances one breakdown a stage, or all where possible |
| `rms_setCondition <0.0-1.0>` | Sets Condition on every enabled system |
| `rms_setSystemCondition <system> <0.0-1.0>` | Sets Condition on one system |
| `rms_setSystemStress <system> <value>` | Sets Stress on one system |
| `rms_setSystemStressMultiplier <value> [system]` | Sets the stress accumulation multiplier |
| `rms_setService <0.0-1.0>` | Sets the Service level |
| `rms_resetVehicle` | Resets condition, service, and active breakdowns |
| `rms_reinitializeVehicle` | Recomputes condition from vanilla resale price, as on first load |
| `rms_setExcluded <true\|false>` | Excludes the vehicle or brings it back in; prints the exclusion state without an argument |
| `rms_startService <type> [count]` | Starts `inspection`, `maintenance`, `repair`, or `overhaul` |
| `rms_finishService` | Finishes the active service instantly |
| `rms_getServiceState` | Prints workshop and service state |
| `rms_showServiceLog [index]` | Prints the service log, or one entry in detail |
| `rms_getDebugVehicleInfo [1]` | Prints vehicle debug info, with specializations when given `1` |
| `rms_setDirtAmount <0.0-1.0>` | Sets the dirt level |
| `rms_setFuelLevel <value>` | Sets fuel, as `0.0-1.0` or `0-100` percent |
| `rms_setHorsePower <hp>` | Sets engine power, rescaling the torque curve |
| `rms_setPlowMaxForce <kN>` | Sets max force on the selected or attached plow |
| `rms_resetFactorStats` | Resets accumulated factor statistics |
| `rms_toggleHudDebugView` | Switches the HUD debug view between normal and factor stats |
| `rms_setConfigVar <path> <value>` | Changes a value inside `RMS_Config` at runtime |
| `rms_printSpecVar <path>` | Prints a value from `spec_RealisticMechanicalSystems` |
| `rms_setSpecVar <path> <value>` | Changes a value inside `spec_RealisticMechanicalSystems` |
| `rms_telemetryStart [scenario] [intervalMs]` | Starts CSV telemetry (`default`, `transmission`, `pto` or `exhaust`) |
| `rms_telemetryStop` | Stops telemetry and closes the file |

### Valid system names for RMS console commands

Commands that take a system argument accept these names, case-insensitive:

- `engine`
- `transmission`
- `hydraulics`
- `cooling`
- `electrical`
- `chassis`
- `fuel`
- `pto`

This applies to commands such as `rms_setSystemCondition`, `rms_setSystemStress`, and `rms_setSystemStressMultiplier`.

Examples: `rms_setSystemCondition engine 0.75`, `rms_setSystemStress fuel 0.2`.

### Temperature test commands

The `raw` values drive the physical model; the other two values are the smoothed dashboard readings. Set both members of a pair when preparing a controlled test:

```text
rms_setSpecVar rawEngineTemperature 90
rms_setSpecVar engineTemperature 90
rms_setSpecVar rawTransmissionTemperature 90
rms_setSpecVar transmissionTemperature 90
```

Read the physical temperatures with:

```text
rms_printSpecVar rawEngineTemperature
rms_printSpecVar rawTransmissionTemperature
```

## Changelog

### v0.10.0.0

- Renamed this independent fork to Realistic Mechanical Systems; existing Advanced Damage System saves and settings are migrated automatically
- Reworked used vehicles: condition follows the selected vehicle lifespan, hidden faults can exist at purchase, and reliable brands reduce the risk
- Added physical engine oil, coolant, transmission oil and hydraulic fluid: nine purchasable products in 5, 25 and 200 L containers, manual transfer, contamination and workshop stock; transmission oil leaks can drain the circuit
- Reworked the pre-shift check and workshop fluid service: go or no go verdict, next service, four level gauges and a Top up procedure charged by the missing volume
- Reworked air filter servicing: dusty work clogs the filter, the air blower only cleans it partly, washing does not clean it, and workshop maintenance replaces it; hand tools also reach further
- Added exhaust smoke driven by vehicle age, engine wear, load and active faults, with a local detail setting for each player
- Added tractor drivetrain management: 2WD, 4WD and AUTO modes, differential locks, an automatic parking brake and wind-up wear; Enhanced Vehicle takes over the functions it manages
- Expanded the HUD with tractor, towed and combined mass, dashboard indicators, and separate engine and transmission thermal alerts
- Added automatic diesel preheating in cold weather, with a four-stage glow plug breakdown
- Reworked transmission thermal wear: temperature responds to the pump, power take-off and heavy low-speed work; cold oil progressively increases wear only under real driveline load; CVT gearboxes can suffer thermostat failure
- Rebuilt hydraulic wear and breakdowns around actual machine capability, pump operation, lifted mass and vibration
- Added a dedicated power take-off system with drive coupling, output bearing and engagement control breakdowns
- Rebalanced mechanical wear: radiator clogging reduces cooling, cooling wear requires an engine above target temperature, cold-engine wear requires high load, turbo wear applies from 75 hp, steering follows angle and axle load, and lubrication covers every non-road machine
- Reworked vehicle eligibility and non-player vehicles: supported motorized machines are classified by capability, AI workers cause normal wear, and contract machines show hours without wearing down
- Improved idling: an unattended running engine now consumes fuel
- Added a global settings profile for new savegames and a fleet reset based on the selected vehicle lifespan; removed the thermal sensitivity, warm-up boost and cooling slowdown settings
- Removed the work process system, harvest wear and the unloading auger breakdown; production years are now resolved internally without Vehicle Years
- Reworked the workshop, inspection, report, maintenance log and leased-vehicle return interfaces; simplified the on-foot vehicle info box to condition and next service
- Expanded tutorial tips for the fluid, smoke, drivetrain, parking brake and thermal systems
- Added 12 languages (27 total) and improved existing translations

## Support

- [GitHub Issues](https://github.com/Squallqt/FS25_RealisticMechanicalSystems/issues)
- [GitHub Discussions](https://github.com/Squallqt/FS25_RealisticMechanicalSystems/discussions)

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) for the complete terms and [NOTICE.md](NOTICE.md) for provenance and attribution.
