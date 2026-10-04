# FS25_RealisticMechanicalSystems

In-depth vehicle wear, failure, diagnostics, maintenance, and repair system for Farming Simulator 25.

[![Version](https://img.shields.io/badge/version-0.11.0.0-blue.svg)](#)
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

1. **Follow the service interval.** Around `10 operating hours` on average by default. Check it in the workshop, in the vehicle info panel, or in the fleet menu (`P` key), then run `Maintenance`.
2. **Prepare your machines daily.** Hold `R` near a vehicle for a pre-shift check, clean it with the `Air Blower`, and grease what needs greasing with the `Grease Gun`.
3. **Do not abuse your equipment.** If it would damage a real machine, it damages this one: overloading, overheating, cold-engine work, wheel slip in mud, oversized implements, speed over rough ground.

## Core Mechanics

RMS tracks Condition and Stress per system, plus the Service of the fluids on one maintenance schedule.

- **Condition**: health and remaining service life. It sets how much abuse a system tolerates before failures become likely. It drops about `1%` per operating hour under normal use, faster under harsh use, and very slowly on a vehicle stored outdoors. Restored by `Overhaul`.
- **Stress**: accumulated strain. It builds through overload, overheating, cold running, wheel slip and other operating or environmental factors. Breakdown probability rises as Stress approaches that system's current Condition. Reduced by preventive maintenance, by repairs, and automatically once a breakdown occurs.
- **Service**: the state of oils, filters, and fluids. It falls with operating hours, and a low level accelerates Condition loss in the systems covered by the overdue fluid, the engine most of all. Restored by `Maintenance`.

Inspection reports give an approximate status (`OPTIMAL`, `REQUIRED`, `OVERDUE`). Exact percentages are shown by a full defectoscopy or an overhaul report. A full defectoscopy is slow and expensive, and rarely worth it: following the recommended interval works better than measuring.

## Wear Factors

Normal wear depends on system activity. Hydraulics and PTO wear only while active; the other enabled systems retain their idling and downtime wear. Passive wear continues outdoors and stops under cover; it also affects the service level. Overdue service adds wear while the affected system operates, and poor-quality consumables increase overall Condition wear.

| System | Wear factors |
| --- | --- |
| **Engine** | Load above `85%`; air filter clogged past `50%`; cold running below `50C` at high RPM load; overheating above `95C` under load; oil level under `50%` |
| **Transmission** | Sustained pull above `85%` load, with an accumulation window scaling from `30` to `90` seconds; lugging (high load, low RPM); wheel slip above `5%` under `20 km/h`; heavy trailer below `10 hp/t` (`6 hp/t` for trucks); a load held on oil below `45C`; on CVT, overheating above `100C`; oil level under `50%` |
| **Hydraulics** | Pump running whenever the engine runs; lifted implement mass on the linkage; vibration while carrying an implement over rough ground; qualified hydraulic movement; cold oil proxy below `30C`; hot oil proxy above `90C`; fluid level under `50%` |
| **Cooling** | Thermostat past `95%` open while the engine is more than `3C` over its target; engine above `95C`; cold shock below `50C` at high RPM load |
| **Electrical** | Lights on; rain, snow, or hail on an outdoor vehicle; starter cranking; engine above `95C`; vibration over rough ground at speed |
| **Chassis** | Poor lubrication on machines that require greasing; vibration over rough ground at speed; steering under `4 km/h`, scaled by the steered angle and by the load the steered axle really carries; braking above `2 km/h` while towing |
| **Fuel** | Fuel below `20%`, aggravated by load; fuel colder than `20C` above `50%` load; idling past `60` seconds; fuel consumption above `80%` of the configured maximum |
| **PTO** | Active drive; native PTO utilization above `40%`, reaching its full factor at `90%`, then overload up to `120%`; a liftable implement turning while raised; every engagement wears the clutch, and engaging above idle shocks the driveline, harder with a bigger implement; sprayers and spreaders, which the game switches to open their sections and lets work at any height, are spared engagement and raised wear |

AI workers use the same wear model, with raised-PTO wear skipped during their automated headland turns. They are protected by behaviour instead: the helper drives like a careful driver. It slows down as soon as the machine counts an overload, whether from low revs, a long hard pull, wheel slip or overheating, never below `5 km/h`, the game's own field work floor, and picks its pace back up once the load eases. It never stalls and is never blocked by a hard start. An overload never sends it home; only a breakdown that leaves the machine unable to work stops it. The game's helpers, Courseplay and AutoDrive are all driven this way, contract machines included, and the player's cruise control speed is never touched.

## Breakdowns

Breakdown probability depends entirely on how close a system's Stress is to its Condition. Condition also sets the chance of a **critical** failure, one that appears straight at stage 4 and skips the rest. The type is drawn with weights based on the wear factors that have been active most.

Most breakdowns run through four stages, **Minor**, **Moderate**, **Major**, and **Critical**, each costing more to repair than the last. Progression is context-dependent; some faults only worsen while the machine performs the work that causes them. Most dashboard warnings on modern vehicles appear from stage 2, though some faults can warn from stage 1. Early faults also show themselves through symptoms: fluctuating RPM, coloured exhaust smoke, knocking, squealing. Catching one there costs almost nothing.

Beyond individual failures, low Condition triggers a permanent **General Wear and Tear** effect: an old machine loses engine power, transmission bite, battery performance, and cooling efficiency even with nothing formally broken.

### Reading the smoke

The exhaust plume is a real diagnostic channel, not decoration. Its colour comes from three mixed sources, its density from how bad things are.

| Colour | What it means | Usual causes |
| --- | --- | --- |
| Black | Too much fuel for the available air | A hard pickup before the turbocharger catches up, lugging at low revs, overload, clogged air filter, worn turbocharger, failing injectors, ECU fault |
| Blue | The engine is burning its own oil | Worn engine at low Condition, leaking turbocharger seals, valve train wear |
| White | Fuel leaving the engine unburnt | Cold engine, failed glow plugs, failing injection or a starving fuel system |

Production year matters as much as condition. With the same fault, an older machine generally smokes more, and a recent one running AdBlue shows almost nothing until something actually breaks. A cold start still shows on a recent machine, briefly, because high injection pressure and glow plugs improved far less than particulate control did.

The plume is drawn as real smoke puffs: each one leaves the pipe as a hot jet that slows, widens and thins as it mixes with the air, rises with the heat of the gas, then drifts with the wind and its eddies. A clean plume dissipates at once; a loaded one hangs and takes seconds to clear. It follows the gas the engine actually moves, from a few metres per second at idle to some thirty at full power: under load the plume shoots up before the wind bends it over and carries far more smoke downwind, while an idling engine lets it curl over at the pipe and fade within a metre or two. On a turbocharged machine, black smoke appears whenever the fuel outruns the air: for a moment on a hard pickup while the turbocharger spools up, and for as long as it lasts on an engine held at full load down at low revs. A naturally aspirated engine never shows either, since without boost its air flow follows the engine speed alone.

Cold air adds a white trail that says nothing about the engine. Below about `8 °C`, the water the combustion produces condenses as the gas mixes with the air, more so in damp weather, and evaporates within a metre or two. Unlike unburnt fuel, it lasts as long as the air stays cold, even on a warm and healthy engine.

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
| Turbocharger Wear | Engines from `56 kW` (`75 hp`) | Half the engine torque lost; stalling can occur |
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
| PTO Engagement Control Malfunction | Vehicles from `1990+` with a physical PTO output | PTO engagement becomes unreliable, then impossible |
| Brake Malfunction | Wheeled | Braking impossible |
| Bearing Wear | Wheeled | Wheel rotation blocked |
| Steering Linkage Wear | Wheeled without tracks | Directional control unsafe |
| Track Tensioner Malfunction | Tracked | Running gear can seize |
| Thermostat Malfunction | All non-electric | Thermostat stuck at its current opening; engine may overheat or warm up poorly |
| Coolant Leak | All non-electric | Safe engine temperature unreachable |
| Fan Clutch Failure | All non-electric | Cooling airflow insufficient |
| Fuel Pump Malfunction | All non-electric | No fuel delivered to the engine |
| Fuel Injector Malfunction | All non-electric | Engine will not run correctly, may not start |
| Fuel Filter Clogging | All non-electric | Fuel flow insufficient to run |
| Fuel Line Air Leak | All non-electric | Fuel supply cannot be maintained |

</details>

## Workshop

The workshop offers Inspection, Maintenance, Repair, Overhaul, fluid Top up and Repainting. By default, work takes in-game time and pauses overnight at the dealer; farm and mobile workshops remain open. Separate settings can make maintenance and repair, overhauls or repainting instant.

Every price is a real dealer's price for the machine's size, its engine or, for paint, its body, with overhaul prices capped against the machine's purchase price. The Economic Difficulty scales it like the game's wages, and the Maintenance Interval, not the price, sets how often the bills come.

- **Inspection**: `Visual` is quick but can miss things, `Standard` detects faults and reports condition, `Complete Defectoscopy` can reveal hidden faults and defective repair parts and gives exact values.
- **Maintenance**: every service falls due on the Maintenance Interval and changes the engine oil; every second one also changes the transmission and hydraulic oil, every tenth one the coolant, as on a real service schedule. The on-foot info box names the maintenance that is due with the hours left, highlighted once it is late, and the workshop opens on it: `Standard` changes the engine oil and blows out the air filter; `Extended` changes every oil and replaces the air filter; `Preventive` changes every fluid, replaces the air filter and also strips Stress from the worst systems. A lighter level than the one due leaves its change overdue until the level is done. Fluids a level does not change are topped up. The bill lists labour and filters, plus the fluids. The cost is **fixed**, so servicing at `90%` costs the same as at `10%`.
- **Repair**: `Quick Fix` suppresses the symptoms without fixing the fault, which returns. `Standard` replaces the failed part and cuts Stress. `Advanced` replaces everything around it and zeroes Stress.
- **Dealer warranty**: for an owned vehicle under 12 months and 20 operating hours, a `Standard` repair with `Original` parts and the fluids required by that repair is free at the dealer. Farm and mobile workshops charge normally.
- **Top up**: fills whatever fluid the machine is missing, for the price of the fluids alone. Quick, and the button disappears once everything is full.
- **Overhaul**: available when at least one system falls below `50%` Condition. `Partial` brings the selected system to at least `75%`; `Standard` brings every system to at least `75%`; `Full` restores every system to `100%`. Every tier clears Stress and supported breakdowns in the systems it treats. Standard and Full also renew Service and replace fluids.
- **Repainting**: `Touch-Ups` repair minor paint damage without changing colours. `Full Repaint` renews the finish and lets you keep the current colours or choose from the vehicle's own configurable colours, including compatible added configurations. Changing colours through the dealer's vehicle configurator also incurs the RMS repaint price.

Maintenance and repair let you pick part quality between `Used`, `Aftermarket`, `OEM`, and `Premium`. Cheaper parts are more often defective: on maintenance they shorten the interval and accelerate wear, on repair they bring the same fault back. Complete Defectoscopy can reveal defective repair parts; poor maintenance consumables remain hidden.

## Pre-Shift Care

- **Pre-shift check**: hold `R` near a vehicle for a go or no go verdict, the machine and its next service, the four fluid levels, radiator and air filter fouling, and reveal faults a real visual check would catch. Takes seconds, works anywhere.
- **Fluids**: engine oil, coolant, transmission oil and hydraulic fluid each have a level, read against the minimum mark of their gauge. Engine oil is burnt off with the work done, faster under load and much faster as the engine wears, so a healthy engine always reaches its next service above the mark whatever interval you set while a tired one asks to be topped up; the other three only drop through a leak. Under the mark the machine only asks for a top up and still works normally; it is under `50%` that a machine short of coolant or transmission oil runs hot, and one short of engine oil or hydraulic fluid wears faster. The workshop `Top up` service fills what is missing for the price of the fluids, maintenance and overhaul replace the fluids covered by the selected procedure, and a repair puts back what the fault it fixed had let out.
- **Wrong fluid**: manually transferring an incompatible product contaminates only the selected circuit. Depending on the proportion in the mixture, system wear can rise to three times its normal rate, heat can increase, and contaminated hydraulic fluid can slow hydraulic functions by up to `25%`. The transfer requires explicit confirmation, and only a complete fluid replacement clears the contamination. Workshop procedures only reserve compatible products.
- **Air Blower**: clears dust from the cooling pack and the air filter. Blowing an air filter out only recovers part of it, since what is embedded in the media stays until Extended or Preventive maintenance replaces it. Washing the vehicle exterior does not clear either component. Their clogging speed follows the game's dirt speed independently of the RMS service interval.
- **Grease Gun**: restores lubrication on machines that need it, harvesters above all. Lubrication drops `10%` per period only if the machine was neither operated, greased, nor serviced during it; inspection alone does not count.
- **Aiming a hand tool**: point it directly at the machine within `5 m`.

## Reliability and Maintainability

Every brand carries two ratings based on its real-world reputation, both shown in the shop.

- **Reliability** slows Condition loss and Stress accumulation, and lengthens service intervals. Premium European and American brands generally rate higher than budget or older Eastern European ones.
- **Maintainability** cuts the money and time of workshop operations. Simple older machines usually beat modern electronics-heavy ones.

Vehicles also age: production year drives thermostat behaviour, overheat protection, how much the machine smokes, and which breakdowns can occur at all.

The `Exhaust Smoke` setting turns the model on or off for the server. Turning it off restores the vehicle's native exhaust.

## Buying Used

A used machine arrives with the wear its hours have earned, and it may carry a fault nobody declared. Nothing shows at the sale.

At the default Vehicle Lifespan, the hours set the odds and the brand shifts them:

| Hours on the clock | Reliable brand | Budget brand |
| --- | --- | --- |
| 10 h | 7% | 11% |
| 25 h | 18% | 28% |
| 45 h | 32% | 51% |

Run an `Inspection` before the machine sees any work. `Standard` checks for active faults; `Complete Defectoscopy` also checks for hidden faults and defective repair parts and gives the exact condition of every system, but can still miss a fault. Skipping that step is how a bargain becomes a breakdown in the middle of a field.

A machine loses value with the hours it has run against the Vehicle Lifespan, then with age, as the game depreciates it; its condition shades that value, and the repairs and paint it needs are taken off. An overhaul restores condition and clears covered faults, but does not reset depreciation from hours and age: late in life, a big repair can cost more than the machine is worth, and replacing it becomes the better deal.

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

The **Telwin Doctor Charge 155 Connect on its Diagnostic trolley** costs **800 €** in **Construction > Buildings > Tools**, following the native mobile cart purchase path. Push it within **4 m** of a stationary RMS vehicle belonging to your farm, stop its engine, and use **Connect charger** on foot. Choose **Charge a battery (150 A)** or **Starting aid (START, 200 A)**, then select the vehicle if several are eligible. These are the manufacturer's rated currents at 12 V. No current adjustment is needed.

Charging continues while you work elsewhere, follows the game's time speed and resumes after loading the save; no charging takes place while the game is closed. The current falls as the battery fills. Disconnect before starting, or reconnect in START mode. In START, the charger supplies up to 200 A only while the starter turns; once the engine runs, it supplies no current and prompts you to disconnect. Wait 30 real seconds between attempts. Starting aid does not guarantee a successful start: Telwin recommends charging a weak battery before trying again. It does not repair battery faults or wear.

The HUD and charger display use the same circuit voltage as the vehicle HUD, together with battery level and actual delivered current. Notifications confirm the connected vehicle, disconnection, completion and interruptions. Use **Disconnect charger** at any time, including after a full charge. Moving the trolley within 4 m does not interrupt the connection. Moving the connected vehicle, workshop work, leaving range or an invalid connection disconnects it and clears the old readings. A charger and jumper cables cannot be connected together. Charge and starting aid both use the existing server electrical calculation; clients do not add their own charge.

Diesel preheating starts automatically below `25 C`. It remains short in mild weather and lengthens progressively as the engine gets colder. At `5 C` and above, failed glow plugs can make the start rough but do not block it solely because of preheating; below that point, their condition becomes start-critical.

## Installation

1. Place the mod ZIP file into your FS25 `mods/` directory (do not extract).
2. Activate the mod in mod selection.
3. Access RMS from the fleet menu (`P` key), the in-game settings, and workshop interactions.

> **Important:** Do not run RMS and Advanced Damage System together. RMS steps aside when it finds ADS and leaves it in charge, so nothing runs twice. Removing ADS is enough: RMS then picks up the condition, the service history and the settings of your fleet from the savegame.

## Usage

### Running a service

1. Take the vehicle to a workshop. Available services depend on the workshop type.
2. Pick `Inspection` first if you are unsure what is wrong, then choose the needed service, including `Top up` or `Repainting`.
3. Review the available options, price and duration before starting.
4. Read the report afterwards when the procedure provides one. The maintenance log keeps every past procedure.

### Reading the warning signs

1. Watch the dashboard indicators, which generally light from stage 2 on modern vehicles; some faults can light them earlier.
2. Listen for knocking, whistling, and grinding, and read the exhaust: black means the engine is choking on fuel it cannot burn, blue means it is burning oil, white means fuel is leaving the engine unburnt. Most stage 1 faults otherwise have no dashboard warning.
3. Run a pre-shift check when something feels off, then a workshop inspection if it does not clear.
4. Repair early. A stage 1 fault costs a fraction of a critical one.

### Leaving a machine out of RMS

1. Open the fleet menu (`P` key) and select the machine.
2. In the `RMS Vehicles` tab, press `X` (`Exclude from RMS`): the machine stops wearing and moves to the `Other Vehicles` tab.
3. In the `Other Vehicles` tab, the `Reason` column says why each machine is left out, and `X` (`Include in RMS`) brings a machine back in. A machine that was never tracked starts from its resale value, like a used one.
4. Electric machines always stay out, and so have no button. On a server, only an admin can make this choice, and a machine under a workshop procedure cannot be excluded until it is done.

## Console Commands

For testing and debugging. Most require you to be inside a vehicle that supports the mod. Commands that change shared gameplay state are relayed to the server and require admin rights when issued by a client. Local display commands and the exhaust override stay on the client.

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
| `rms_setService [0.0-1.0] [engine\|transmission\|coolant]` | Sets one service clock, or all three without a clock name; defaults to `1.0` |
| `rms_resetVehicle` | Resets service clocks and clears active breakdowns |
| `rms_reinitializeVehicle` | Recomputes condition from vanilla resale price, as on first load |
| `rms_reinitializeFluidCapacities` | Recomputes physical fluid capacities for the current vehicle |
| `rms_setExcluded <true\|false>` | Excludes the vehicle or brings it back in; prints the exclusion state without an argument |
| `rms_getServiceState` | Prints workshop and service state |
| `rms_showServiceLog [index]` | Prints the service log, or one entry in detail |
| `rms_getDebugVehicleInfo [1]` | Prints vehicle debug info, with specializations when given `1` |
| `rms_setDirtAmount <0.0-1.0>` | Sets the dirt level |
| `rms_setFuelLevel <value>` | Sets fuel, as `0.0-1.0` or `0-100` percent |
| `rms_setHorsePower <hp>` | Sets engine power, rescaling the torque curve |
| `rms_setPlowMaxForce <kN>` | Sets max force on the selected or attached plow |
| `rms_resetFactorStats` | Resets accumulated factor statistics |
| `rms_toggleHudDebugView` | Switches the HUD debug view between normal and factor stats |
| `rms_exhaustOverride <opacity\|-> [flow\|-] [vapour\|-]` | Overrides exhaust rendering locally for all machines; `-` keeps each engine's value and `off` clears the override |
| `rms_setConfigVar <path> <value>` | Changes a value inside `RMS_Config` at runtime |
| `rms_printSpecVar <path>` | Prints a value from `spec_RealisticMechanicalSystems` |
| `rms_setSpecVar <path> <value>` | Changes a value inside `spec_RealisticMechanicalSystems` |

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

This applies to commands such as `rms_setSystemCondition` and `rms_setSystemStress`.

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

### v0.11.0.0

- Added the Telwin Doctor Charge 155 Connect on a trolley for 800 €: recharge a battery while you work or select START to help start a vehicle. Charging follows the game's time speed
- Removed the System Stress Rate setting and its console command
- Removed the Passive Wear setting
- Removed the Smoke Intensity setting
- Removed the Plume Detail setting
- Reworked the exhaust smoke into a realistic plume that rises higher under load and drifts with the wind
- Added white exhaust vapour in cold and damp weather
- Removed the Park Vehicle During Maintenance setting
- Removed the Warranty setting; dealer warranty now covers standard repairs with original parts and required fluids under 12 months and 20 hours
- Removed the Procedure Duration Multiplier setting
- Removed the Procedure Price Multiplier setting
- Removed the Clogging Speed setting; radiator and air filter clogging now follow the game's dirt speed independently of the RMS service interval
- Removed the Differential Lock Release Speed setting; the lock now releases above 10 km/h
- Removed the Pre-shift Check Duration setting; the check now lasts as long as its sound
- Removed the Grease Consumption Rate setting; grease now drops 5% per operating hour
- Removed the AI Overload and Overheat Control, Stop AI on Critical Overload, Contract Vehicle Protection, AI Sensitivity and AI Minimum Speed settings; every AI worker now drives with care on its own
- Added Repainting to the workshop: repair paint damage or choose new colours, including through dealer configuration at the RMS repaint price
- Added separate instant completion settings for maintenance and repair, repainting, and mechanical overhauls
- Fixed the issue preventing vehicles from starting with the GIANTS Ignition Key
- Reworked overhauls for predictable results: Partial and Standard bring systems into good condition; Full restores them to like new
- Added compatibility with FS25_mobileWorkshop: inspections and repairs can now be started from its mobile workshop
- Improved the workshop, inspection report, and maintenance log interfaces
- Simplified maintenance deadlines, now shown in whole hours
- Fixed double charges when using farm-owned fluids for workshop top-ups
- Fixed some modded trucks and machines being ignored by RMS
- Fixed an empty hydraulic oil circuit that could never be refilled on some cars and utility vehicles; they no longer have hydraulics in RMS
- Fixed a full overhaul being undone when the save was reloaded
- Fixed parked machines missing from the RMS fleet list for players joining a server
- Fixed some modded cars clogging their radiator and air filter on the road
- Fixed grease and fluid leaks draining far too fast with the Ingame Time Operating Hours mod
- Removed RMS Reliability and Ease of Maintenance ratings from the shop for machines RMS does not track
- Added to the Other Vehicles tab why each vehicle is left out of RMS, with a button to include or exclude it
- Rebalanced fluid capacities to match the size of each machine's engine
- Added a line-by-line bill and the cost per operating hour to the Technical Record
- Added a single transmission and hydraulic oil to most tractors, as in reality; Fendt, Valtra and Lindner keep two separate oils
- Added a maintenance schedule set on the Maintenance Interval: every service changes the engine oil, every second one the transmission and hydraulic oil, every tenth one the coolant; the vehicle info box names the maintenance that is due, the workshop opens on it, and each level says what it changes
- Removed the Minimal maintenance; the workshop Top up refills the fluids
- Fixed fluid barrels arriving empty on maps and mod lists that add many products; barrels no longer depend on the game's fill types. Fluid containers already present in a save will disappear after the update; new ones must be purchased.
- Fixed the vehicle value in the RMS workshop showing 10% more than selling from the menus pays; it now matches the RMS fleet list
- Reworked workshop prices: inspections, maintenance, repairs, overhauls and repainting now cost real dealer prices sized on the machine and scaled by the Economic Difficulty, instead of a share of its price and age; the maintenance bill shows labour and filters
- Reworked the vehicle value: it now falls with the hours run against the Vehicle Lifespan, then with age; an overhaul restores condition but does not reset age or operating hours
- Changed the default Maintenance Interval from 5 to 10 hours
- Fixed the noises of worn bearings, vibrations and seized wheels no longer changing with speed above 15 km/h
- Fixed the pre-shift check sound not playing on a parked machine
- Fixed the breakdown noises of an idling machine going unheard by other players on a server
- Fixed AI workers, Courseplay and AutoDrive stopping in the field under a heavy load, even without overheating
- Reworked the AI worker's driving: it slows down while the machine is overloaded, never below 5 km/h, and picks its pace back up once the load eases
- Fixed the player's cruise control speed being replaced by the machine's top speed after an AI worker's job
- Reworked PTO wear: engaging it at high engine speed, engaging it often, running it with the implement raised and overloading it now strain it
- Fixed fluid transfers from a container sometimes needing several key presses to start
- Added the choice of the circuit to fill, then of the fluid to pour, when several are possible

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
