# FS25_RealisticMechanicalSystems

In-depth vehicle wear, failure, diagnostics, maintenance, and repair system for Farming Simulator 25.

[![Version](https://img.shields.io/badge/version-1.0.0.0--beta.1-blue.svg)](#)
[![FS25](https://img.shields.io/badge/FS25-compatible-green.svg)](https://farming-simulator.com/)
![Multiplayer](https://img.shields.io/badge/multiplayer-supported-success.svg)
![Languages](https://img.shields.io/badge/languages-27-blue.svg)
[![License](https://img.shields.io/badge/license-GPL--3.0-yellow.svg)](LICENSE)

Every machine is built from up to 8 individual systems, each with its own condition, its own wear factors, and its own way of failing. Service on schedule, work the machine within its limits, and watch for the early symptoms: the cheapest repair is always the one you catch first.

Singleplayer, multiplayer, and dedicated server.

Electric vehicles are tracked with the parts they really have: an electric motor, a traction battery and power electronics.

> **Note:** This repository is an independently maintained fork of Advanced Damage System by id577, developed by Squallqt since 30 June 2026. The gameplay model and the documentation have been substantially reworked since then; the original credits and provenance are preserved unchanged in [NOTICE.md](NOTICE.md).

## Quick Start

Three rules are enough to play without constant breakdowns:

1. **Follow the service recommendation.** Maintenance spacing adapts each vehicle’s service intervals to your playing time; each fluid can also reach its calendar limit. Check it in the workshop, in the vehicle info panel, or in the fleet menu (`P` key), then run `Maintenance`.
2. **Prepare your machines daily.** Hold `R` near a vehicle for a pre-shift check, clean it with the `Air Blower`, and grease what needs greasing with the `Grease Gun`.
3. **Do not abuse your equipment.** If it would damage a real machine, it damages this one: overloading, overheating, cold-engine work, wheel slip in mud, oversized implements, speed over rough ground.

## Core Mechanics

RMS tracks the wear of the parts of each system, the Condition each system draws from them, plus the Service of the fluids on one maintenance schedule.

- **Parts**: each system is made of the parts that fail in it, the oil pump, the valve train and the turbocharger of an engine, the brakes, the wheel bearings and the steering linkage of a chassis. Every part wears with the hours of its system, and faster under what wears it on a real machine: driving against the applied parking brake wears the parking brake, an engine pushed cold its valve train, an overdue service its oil pump. A cause known to wear no part in particular wears the whole system evenly. The causes of each part come from manufacturer manuals and published studies.
- **Condition**: health and remaining service life of a system, the average of its parts. It drops about `1%` per operating hour under normal use, faster under harsh use, and very slowly on a vehicle stored outdoors. A repair renews the part it replaces; `Overhaul` restores every part of the systems it covers.
- **Service**: the state of oils, filters, and fluids. It falls with operating hours, and a low level accelerates Condition loss in the systems covered by the overdue fluid, the engine most of all. Restored by `Maintenance`.

Inspection reports give an approximate status (`OPTIMAL`, `REQUIRED`, `OVERDUE`). Exact percentages are shown by a `Complete` inspection or an overhaul report. A `Complete` inspection is slow and expensive, and rarely worth it: following the recommended interval works better than measuring.

A report describes the machine on the day it was written. `Last check` gives its age in hours of work. Once the machine shows a fault the report did not list, or has worked half a service interval since, the report stays on screen greyed out under a `Recheck` mark, in the fleet menu, the workshop, the vehicle list of the game's statistics page and the box shown when you look at the machine. An inspection, a maintenance or an overhaul writes a new one.

Each report also tells how much faster than normal the machine has worn since RMS follows it, and the three causes that weighed the most, such as an overloaded engine, wheel slip or late servicing. The pace reads green while it stays normal, then yellow, orange and red as it reaches twice the normal wear. Reports written before this version do not have it.

## Wear Factors

Normal wear depends on system activity. Hydraulics and PTO wear only while active; the other enabled systems retain their idling and downtime wear. Passive wear continues outdoors and stops under cover; it also affects the service level. Overdue service adds wear while the affected system operates, and poor-quality consumables increase overall Condition wear.

| System | Wear factors |
| --- | --- |
| **Engine** | Overload; low RPM under heavy load; air filter clogged past `50%`; cold running below `50C` above `85%` load; overheating above `95C` under load; oil level under the minimum mark |
| **Transmission** | Sustained excessive pulling effort, with an accumulation window scaling from `30` to `90` seconds; lugging (high load, low RPM); wheel slip above `5%` under `20 km/h`; heavy trailer below `10 hp/t` (`6 hp/t` for trucks); a load held on oil below `45C`; on CVT, overheating above `100C`; oil level under `50%` |
| **Hydraulics** | Pump running whenever the engine runs; a load on its way up, raised by the linkage, a loader or forks, in proportion to its weight: the implement, the bucket and what it holds, a bale or a pallet; a load held raised costs nothing more; an implement bouncing on the linkage over rough ground, in proportion to its weight and in full from a third of the machine's own; hydraulic movements; cold oil below `30C`; hot oil above `90C`; fluid level under `50%` |
| **Cooling** | Thermostat past `95%` open while the engine is more than `3C` over its target; engine above `95C`; cold shock below `50C` at high RPM load |
| **Electrical** | Lights on; rain, snow, or hail on an outdoor vehicle; starter cranking; engine above `95C`; vibration over rough ground at speed, a quarter as hard as on the chassis |
| **Chassis** | Poor lubrication on machines that require greasing; vibration over rough ground at speed, the same on a field as on a track; a collision that stops the machine dead or takes `10 km/h` or more off it at once, faster than its tyres could ever slow it, which costs `1%` of Condition per `10 km/h` lost, up to `5%`; turning the steering under `4 km/h`, counted by how far the wheels are turned and scaled by the grip of the ground and the load the steered axle really carries, wheels held turned costing nothing; braking above `2 km/h` while towing |
| **Fuel** | Fuel below `20%`, aggravated by load; fuel colder than `20C` above `50%` load; idling past `60` seconds; fuel consumption above `80%` of the configured maximum |
| **PTO** | Active drive; PTO load above `40%`, reaching its full factor at `90%`, then overload up to `120%`; a liftable implement turning while raised; every engagement wears the clutch, and engaging above idle shocks the driveline, harder with a bigger implement; sprayers and spreaders are spared engagement and raised wear |

AI workers use the same wear model, minus what a careful driver avoids and a worker cannot: working the machine before it has warmed up, the PTO turning raised during their automated headland turns, engaging the PTO above idle, steering at a crawl, driveline windup, collisions, and wheels spinning on the spot. Otherwise they are protected by behaviour: the helper drives like a careful driver. It slows down as soon as the machine counts an overload, whether from low revs, a long hard pull, wheel slip or overheating, never below `5 km/h`, the game's own field work floor, and picks its pace back up once the load eases. It never stalls and is never blocked by a hard start. An overload never sends it home; only a breakdown that leaves the machine unable to work stops it. The game's helpers, Courseplay and AutoDrive are all driven this way, contract machines included, and the player's cruise control speed is never touched.

## Breakdowns

A breakdown is a part that fails, as real parts of its kind do. Each part follows the failure data published for its kind of component, bearings, clutches, seals, pumps, valves, electronics or batteries: most fail at random with a risk that rises little with age, a few wear out and fail more readily as they age, and electronics fail most when new. A part ages with the work of the machine, a whole machine life being the vehicle lifespan of the settings: in normal use a machine breaks down about twelve times over that life, a little more often as it ages, and goes through about three batteries. Abuse ages the parts it strains far faster, so they fail sooner. The part that fails is the one the machine has worn: a chassis that braked heavy trailers loses its brakes, one driven against the parking brake its parking brake, one that ran into obstacles its wheel bearings or its steering linkage, and electrics worn by shaking fail at the wiring first. A worn starter turns the engine slower and slower, until a cold engine no longer fires; a shorted alternator diode drains the battery at rest; a parking brake that no longer releases fully drags the machine. A failure appears at its first stage, and a part that can fail in several real ways fails in one of them, kept until the repair: an alternator by its regulator or by its diodes, a head gasket towards a cylinder, outside or into the oil.

Most breakdowns run through four stages, **Minor**, **Moderate**, **Major**, and **Critical**, each never cheaper to repair than the last: a repair costs the real parts it replaces, more once the fault has damaged others. Progression is context-dependent; some faults only worsen while the machine performs the work that causes them, and every fault worsens faster while the causes that wore its part go on. Within a stage, its symptoms grow gradually towards those of the next one; the dashboard warnings and the new symptoms of the next stage wait for it. Most dashboard warnings on modern vehicles appear from stage 2, though some faults can warn from stage 1. Early faults also show themselves through symptoms: fluctuating RPM, coloured exhaust smoke, knocking, squealing. Catching one there spares the parts it would go on to damage.

A part also shows its wear before it fails. From a third of its life it slowly takes on its symptom, in full at the end of that life: worn piston rings, liners, pistons and valves cost engine power, burn oil into blue smoke, raise fuel consumption and make a cold start harder; a worn turbocharger costs power and burns oil; injectors drink more; a worn clutch slips; a worn hydraulic pump slows the hydraulics; worn brakes brake less; a worn radiator cools less; a sulfated battery holds less and a worn alternator charges less; from two thirds of its life a worn steering linkage lets the steering float. On an electric machine a worn motor costs power and draws more, and corroded wiring leaks current. A symptom several parts share comes from the most worn of them, never from their sum. A new part takes its symptom away, and an engine rebuild renews the whole kit: the top end its valves, guides and head gasket, the bottom end its pistons, rings, liners and bearings as well.

A damaged steering never loses its lock. A worn linkage gives the wheels play, up to `2.5` degrees: small corrections at the wheel do nothing, every blow of the suspension kicks the wheels inside that play, harder with speed, and a badly worn front end shakes between `25` and `45 km/h`. A bent linkage toes one wheel off, up to `1.2` degrees, and the machine pulls to that side, left or right, settled when the breakdown appears. At the last stage a rod end lets go: one wheel trails on its own, steady at walking pace and fluttering ever harder from `8` to `25 km/h`. The game's helpers, Courseplay, AutoDrive and the steering assist drive on the same wheels and take the same faults. No dashboard lamp warns of any of it: a rod end carries no sensor.

### Reading the smoke

The exhaust plume is a real diagnostic channel, not decoration. Its colour comes from three mixed sources, its density from how bad things are.

| Colour | What it means | Usual causes |
| --- | --- | --- |
| Black | Too much fuel for the available air | A hard pickup before the turbocharger catches up, lugging at low revs, overload, clogged air filter, worn turbocharger, failing injectors, ECU fault |
| Blue | The engine is burning its own oil, and its sump goes down as fast as it smokes | Worn or failed piston rings, liners, pistons, valve guides and seals, leaking turbocharger seals |
| White | Fuel leaving the engine unburnt | Cold engine, failed glow plugs, failing injection or a starving fuel system |

Production year matters as much as condition. With the same fault, an older machine generally smokes more, and a recent one running AdBlue shows almost nothing until something actually breaks. A cold start still shows on a recent machine, briefly, because high injection pressure and glow plugs improved far less than particulate control did.

The plume is drawn as real smoke puffs: each one leaves the pipe as a hot jet that slows, widens and thins as it mixes with the air, rises with the heat of the gas, then drifts with the wind and its eddies. A clean plume dissipates at once; a loaded one hangs and takes seconds to clear. It follows the gas the engine actually moves, from a few metres per second at idle to some thirty at full power: under load the plume shoots up before the wind bends it over and carries far more smoke downwind, while an idling engine lets it curl over at the pipe and fade within a metre or two. On a turbocharged machine, black smoke appears whenever the fuel outruns the air: for a moment on a hard pickup while the turbocharger spools up, and for as long as it lasts on an engine held at full load down at low revs. A naturally aspirated engine never shows either, since without boost its air flow follows the engine speed alone.

Cold air adds a white trail that says nothing about the engine. Below about `8 °C`, the water the combustion produces condenses as the gas mixes with the air, more so in damp weather, and evaporates within a metre or two. Unlike unburnt fuel, it lasts as long as the air stays cold, even on a warm and healthy engine.

Leaving a diesel idling also leaves its mark. Past a long idle under `30%` load, unburnt carbon builds up and darkens the plume. The deposit survives an engine stop and a save, then burns off only once the engine is warm and working under load.

<details>
<summary><strong>Full breakdown list</strong></summary>

| Breakdown | Applies to | Critical effect |
| --- | --- | --- |
| ECU Malfunction | Non-electric, known `2000+` year or AdBlue | Engine cannot be controlled and will not start |
| Corroded Wiring | `2000+` with lights | Lights dead, engine start impossible |
| Battery Sulfation | All | Cranking too weak to start reliably |
| Glow Plug Failure | Diesel | No start when preheating is required |
| Alternator Regulator Failure | All non-electric | No charging, battery reserve only |
| Turbocharger Wear | Engines from `56 kW` (`75 hp`) | Half the engine torque lost; stalling can occur |
| Oil Pump Malfunction | All non-electric | Oil circulation lost, running and starting unsafe |
| Valve Train Malfunction | All non-electric | Engine cannot run correctly, may not start |
| Manual Clutch Wear | Manual transmissions | Clutch burnout, vehicle cannot move |
| Synchronizer Malfunction | Manual and synchro-shift | Shifting impossible |
| Powershift Pump Malfunction | Powershift | Transmission stuck in neutral |
| Variable Transmission Wear | Variable-ratio transmissions | Drive transfer becomes unreliable |
| Ratio Control Malfunction | Variable-ratio transmissions | Ratio control and drive transfer become severely restricted |
| CVT Addon Malfunction | Vehicles using CVT Addon | Complete CVT failure, vehicle cannot move |
| Transmission Thermostat Malfunction | CVT | Thermostat stuck at one opening, the oil either overheats or never warms up |
| Transmission Oil Leak | All | Too little oil left to run the transmission safely |
| Hydraulic Pump Malfunction | Vehicles with hydraulic functions | Hydraulic system inoperable |
| Hydraulic Cylinder Internal Leak | Vehicles with a hydraulic lift | Raised loads drop rapidly |
| Hydraulic Hose External Leak | Vehicles with hydraulic connections | Hydraulic performance strongly reduced |
| Hydraulic Filter Clogging | Vehicles with hydraulic functions | Hydraulic functions barely respond |
| Hydraulic Oil Cooler Malfunction | Vehicles with hydraulic functions | Hydraulic work overheats the oil |
| Hydraulic Control Valve Malfunction | Vehicles with a controllable hydraulic function | One hydraulic function becomes erratic or blocked |
| PTO Drive Coupling Wear | Vehicles with a physical PTO output | PTO power can no longer be transmitted |
| PTO Drive Output Bearing Wear | Vehicles with a physical PTO output | PTO operation becomes impossible |
| PTO Engagement Control Malfunction | Vehicles from `1990+` with a physical PTO output | PTO engagement becomes unreliable, then impossible |
| Brake Malfunction | Wheeled | Braking impossible |
| Bearing Wear | Wheeled | Wheel rotation blocked |
| Steering Linkage Wear | Wheeled without tracks | One wheel no longer follows the steering |
| Track Tensioner Malfunction | Tracked | Running gear can seize |
| Thermostat Malfunction | All non-electric | Thermostat stuck at its current opening; engine may overheat or warm up poorly |
| Coolant Leak | All | Safe engine temperature unreachable |
| Fan Clutch Failure | All non-electric | Cooling airflow insufficient |
| Fuel Pump Malfunction | All non-electric | No fuel delivered to the engine |
| Fuel Injector Malfunction | All non-electric | Engine will not run correctly, may not start |
| Fuel Filter Clogging | All non-electric | Fuel flow insufficient to run |
| Fuel Line Air Leak | All non-electric | Fuel supply cannot be maintained |
| Electric Motor Bearing Wear | Electric | Motor locked, machine will not start |
| Electric Motor Winding Fault | Electric | Motor stopped |
| Motor Position Sensor Fault | Electric | Motor cannot be controlled and will not start |
| Inverter Malfunction | Electric | No power reaches the motor |
| Voltage Converter Failure | Electric | No charging, auxiliary battery reserve only |
| On-board Charger Failure | Electric | Charging at a station impossible |
| High-voltage Insulation Loss | Electric | Machine refuses to start for safety |
| Traction Battery Cell Fault | Electric | A quarter of the capacity lost, machine stopped |
| High-voltage Contactor Failure | Electric | Traction battery no longer powers the machine |
| Coolant Pump Failure | Electric | Cooling almost lost, the machine overheats quickly |
| Reduction Gear Wear | Electric without a gearbox | Reduction gear locked, vehicle cannot move |

</details>

## Workshop

The workshop offers Inspection, Maintenance, Repair, Overhaul, fluid Top up at the dealer, and Repainting. By default, work takes in-game time and pauses overnight at the dealer; farm and mobile workshops remain open. Separate settings can make maintenance and repair, overhauls or repainting instant. Before you start, the recap quotes the bill line by line, as the maintenance log will keep it: labour, filters with the ones fitted, each part and each fluid with its price. Fluids drawn from your own drums at the farm keep their liters without a price; when the workshop zone does not hold enough of one, the quote says how many liters are missing and the order waits for them. A drum needs no pump for this: the pump only serves to top a machine up by hand.

Prices combine estimated labour, parts and required fluids for the machine's size. A maintenance done in your own farm workshop bills no labour: you service the machine yourself and pay its filters, with the fluids taken from your containers; repairs, inspections and overhauls keep their labour there. Repair labour depends on the selected operations and their access; overhaul prices remain capped against the machine's purchase price. Economic Difficulty scales costs like the game's wages. Maintenance spacing controls hourly service deadlines independently of the price.

- **Inspection**: the three types side by side, each with its price and duration. `Visual` looks the machine over and runs it: it finds a mechanical fault four times in five, none of the faults a diagnostic tool reads (calculators, wiring, high voltage), and leaves no report. `Standard` also reads the fault codes, finds every active fault and rates the condition in words. `Complete` also finds the faults that have not shown yet, a defective repair part or a temporary repair, gives exact figures and assesses the failure risk of each system against that of the same system new: `Low` under one and a half times, `Moderate` under twice, `High` beyond. After the breakdowns it lists up to three worn parts, the riskiest first, each with its risk against a new part and what renews it: the adjustment of a service, or the replacement of an advanced repair or an overhaul. The corner of the table gives the age of the last report. The figures of a `Complete` inspection stay on screen after a `Standard` inspection or a maintenance, for as long as that report still describes the machine; a maintenance only renews the Service it measured. Every maintenance level runs the fault search of a `Standard` inspection, so an inspection is never needed before a maintenance; without a diagnostic tool plugged into the machine, the mobile and personal workshops find only the mechanical faults of a machine with an electronic control unit. In the Mechanical Dashboard, each system of the `Condition` card unfolds on its parts as the last `Complete` inspection measured them, the `Failed` and `Worn` ones first; a part that reading does not hold says `Not measured`.
- **Maintenance**: each level is named after its interval in hours on the machine, for example `20 h service`, `40 h service` and `80 h service`. Under its name, each column says how often it comes back: at every service, 1 service in 2, 1 service in 4. The larger ones also do all that the smaller ones do. The first changes the engine oil, tops up the other fluids and cleans the air filter while leaving its embedded wear. The second changes all present oils and the air filter, and tops up coolant. The last changes all present fluids and the air filter, adjusts the valve clearance and checks the injectors and the thermostat: on a combustion machine a worn valve train is set right; injectors and thermostats fail at random at any age, which no check prevents, and no other part is touched. The existing radiator cleaning and lubrication are retained. Each fluid follows its own hourly and calendar limits, whichever comes first. The workshop recommends the lightest service covering the due changes, names the fluid responsible and shows both limits. Only completed fluid replacements restart their deadlines; top-ups and lighter services leave other deadlines unchanged. Maintenance spacing remains freely adjustable, independently of mechanical lifespan. It sets the engine oil interval of a recent machine, on a 500-hour reference. An older machine changes its engine oil as often as its manuals of the time required: at a 10 h setting, a 1970s tractor does it every 4.4 h and a machine from before 1960 every 2 h. The other fluids keep their programme. Calendar limits stay unchanged. The bill retains labour, filters, fluid volumes and part quality.
- **Repair**: `Quick Fix` suppresses the symptoms without fixing the fault, which returns, and fits no part: the part stays worn. `Standard` replaces the failed part with a new one, or a half worn one with `Used` parts. `Advanced` takes twice the time and the price and also replaces the worn parts of the same system. A part is worn once it is older than the age by which one part of its kind in ten has failed and its risk of failing has doubled since it was new: in normal use the bearings, the valve train and the steering linkage get there within the life of the machine, the clutch, the brakes and the turbocharger only when driven hard. The work order sets the three methods side by side, as the maintenance levels: price, duration and what each one does to the fault, its part and the parts beside it.
- **Warranty**: replacement with original parts and its required fluids is covered for 24 months or the hour limit, whichever comes first. A new machine can be bought with 36- or 48-month cover; the shop shows the hour-meter limit and the price for the selected configuration. Dealer repairs are free; mobile repairs retain the extra mobile labor cost. Farm workshop repairs are not covered. A dealer-fitted replacement part is covered for 12 months. A fault that occurs with overdue service for its system is refused on its own; the other faults remain eligible. The repair quote and the recorded invoice show coverage and what you pay.
- **Top up**: at the dealer, fills whatever fluid the machine is missing, for the price of the fluids alone. Quick, and the button disappears once everything is full. On the farm, top up with your own fluid cans.
- **Overhaul**: available when at least one system falls below `50%` Condition. `Partial` brings the selected system to at least `75%`; `Standard` brings every system to at least `75%`; `Full` restores every system to `100%`. Every tier brings each part of the systems it treats to at least that condition, repairs their breakdowns, identified or not, fits new fuel and hydraulic filters and leaves a report with figures. `Partial` changes the oil of its system; `Standard` and `Full` change every fluid, which restarts their deadlines. The work order sets the three tiers side by side, counts the systems below `50%` in its corner and gives the system of a `Partial` overhaul one card each.
- **Repainting**: `Touch-Ups` repair minor paint damage without changing colours. `Full Repaint` renews the finish and lets you keep the current colours or choose from the vehicle's own configurable colours, including compatible added configurations. Touch-ups are done on the farm or at the dealer up to `30%` paint damage, a full repaint at the dealer only. The work order sets both side by side under the paint damage of the machine, and says why one cannot be done where you are. On a machine you own, colours change only through a full repaint: the game's `Customize` screen keeps its other options. Buying a machine in another colour than the one already selected, metallic or not, costs a full repaint.

A fault has to be identified before the workshop repairs it. The dashboard, noises, smoke and the pre-shift check show symptoms; an inspection or a maintenance identifies the fault, and a fault that reaches its last stage shows itself. The workshop says so: a warning light lit by a fault not yet identified is written in orange, and a `Repair` or an `Overhaul` with nothing to do stays open and says why: no fault identified, none ticked, or no system below `50%` Condition.

Maintenance and repair let you pick part quality between `Used`, `Aftermarket` and `Original`, each on a card showing the price of the order, its gap with original parts and the chance of a later defect. Used and aftermarket parts are sometimes defective: on maintenance they shorten the interval and accelerate wear, on repair they bring the same fault back. On a repair, the `Used` card shows the hours of the machine the part comes from, which sets its wear, and its warranty: 3 months on the part, labour excluded, except engine parts from machines past half their life. A `Complete` inspection can reveal defective repair parts; poor maintenance consumables remain hidden.

## Pre-Shift Care

- **Pre-shift check**: hold `R` near a vehicle for a go or no go verdict, the machine and its next service, the four fluid levels, radiator and air filter fouling, and the symptoms a real visual check would catch. Takes seconds, works anywhere. When a symptom comes from a fault the workshop has not identified yet, the check says that an inspection or a maintenance identifies it.
- **Fluids**: engine oil, coolant, transmission oil and hydraulic fluid each have a level, read against the minimum mark of their gauge. Engine oil is burnt off with the work done, faster under load and much faster as the engine wears, at the rates measured on real diesels: a healthy engine worked hard reaches its minimum mark late in its service interval and takes a litre or two, a worn one asks for oil many times per interval; the other three only drop through a leak. A shortage of coolant or transmission/hydraulic oil progressively weakens the cooling of its circuit as the level falls; check the gauges and top up before sustained heavy work. Every level gauge reads like a dipstick: the stretch between its MIN and MAX marks is hatched, and a level that falls below the gauge only shows its red end. Below the minimum mark, low engine, transmission or hydraulic oil also increases wear, more as the level falls; the oil lamp, which reads the oil pressure, lights only once the engine oil is critically low, under `30%`. The dealer's `Top up` service fills what is missing for the price of the fluids, maintenance and overhaul replace the fluids covered by the selected procedure, and a repair puts back what the fault it fixed had let out.
- **Fluid cans**: the game's fill displays identify each product and show its remaining litres. A 5 or 25 L can is carried like any object with the left click, which sets it down where you want. `R` takes it in hand to pour: aim at a machine within `4 m` and hold the left click. The can tops up the circuit made for its fluid first, and the gauge shows the level rising towards its MAX mark. Release the click to stop, and press `R` again to carry the can like any object. The `R` key can be changed in the controls. Switching hand tool or climbing into a machine sets it down for you.
- **Drum pump**: a 200 L drum stays on its pallet and delivers through a battery drum pump, bought with the hand tools. Pump in hand, aim at a drum and click to fit it on the bung; with empty hands, a click on the drum takes the pump back. `R` on a fitted drum takes the nozzle at the end of its `4 m` hose, and `R` again hangs it up. Bring the drum within `4 m` of the machine, aim at the machine and hold the click, as with a can: the pump runs at `1 L/s` for as long as you hold it and stops by itself at the MAX mark. The hose is counted from you to the pump: from `3 m` a warning tells how far it still reaches, as the game does for its pressure washer, and past `4 m` the nozzle is hung up. A drum pumped empty stays until its pump is taken off.
- **Putting containers away**: cans and drums go into a `Bale & Pallet Storage` like any pallet, as long as the building accepts their product. Its list names each container with the liters left in it out of what it holds, and says which drum carries the pump. Each one comes back out as it went in: same format, same liters, pump still fitted.
- **Wrong fluid**: watch what you hold. When the circuit made for its fluid is full, a can or the nozzle of a drum offers the circuit that is short instead. Manually transferring an incompatible product contaminates only the selected circuit, and the pour gauge says `Incompatible Fluid` for as long as it runs. Depending on the proportion in the mixture, system wear can rise to three times its normal rate, heat can increase, and contaminated hydraulic fluid can slow hydraulic functions by up to `25%`. The transfer requires explicit confirmation, which says what the wrong fluid harms on that circuit, and only a complete fluid replacement clears the contamination. Workshop procedures only reserve compatible products.
- **Air Blower**: clears dust from the cooling pack and the air filter. Blowing an air filter out only recovers part of it, since what is embedded in the media stays until the workshop replaces it, from the second maintenance level up. Washing the vehicle exterior does not clear either component. Their clogging speed follows the game's dirt speed independently of the RMS service interval.
- **Grease Gun**: restores lubrication on machines that need it, harvesters above all. Lubrication drops `10%` per period only if the machine was neither operated, greased, nor serviced during it; inspection alone does not count.
- **Aiming a hand tool**: point it directly at the machine within `5 m`.

## Reliability and Workshop Access

Original reliability is shown consistently as `Average`, `Fair`, `Good` or `Very good`. It differs between brands, using qualitative approximations where comparable failure data are unavailable. It affects mechanical wear once; it does not extend an oil change interval or guarantee freedom from breakdowns. Current mechanical condition and maintenance needs remain separate.

`Ease of maintenance` is shown as `Easy`, `Average` or `Demanding` in the shop, fleet, workshop and report. It summarizes intervention complexity. Internal transmission work can take longer on a complex drivetrain; an accessible exterior hose does not receive that surcharge. Comparable Fendt and Case architectures use the same rules. Routine servicing remains possible at a mobile workshop; the quote gives the actual price and wait for the selected work.

Mobile workshops allow maintenance and visual inspections; on a machine with an electronic control unit, their maintenance finds the mechanical faults only. They do no repainting: picking it there says the dealer does it. Some inspections and electronic, high-voltage or heavy repairs require a farm workshop or dealer. A blocked selection explains why and is refused without silently removing selected work. The restrictions and mechanical wear effects can still be disabled independently. Instant options change the wait only.

The three service choices show their covered changes and applicable intervals. `Estimated schedule` reminds that these intervals are RMS approximations, the same for every machine. Calendar observation starts when introduced if no date has been recorded; existing hourly delays and paid work are retained.

Vehicles also age: production year affects how much the machine smokes and which breakdowns can occur.

The `Exhaust Smoke` setting turns the model on or off for the server. Turning it off brings back the game's own exhaust.

## Buying Used

A used machine arrives with the life its previous owner gave it, and the shop shows how they looked after it. A careful owner's machine has its parts worn by its hours alone and each part that failed replaced; a regular owner's a little more, from skipped blow-outs and greasing; a neglected one comes with worn parts and the breakdowns of the hours since its last service, left unrepaired.

Run an `Inspection` before the machine sees any work. `Standard` checks for active faults, electronic ones included; `Complete` also checks for hidden faults and defective repair parts and gives the exact condition of every system, but can still miss a fault. Skipping that step is how a bargain becomes a breakdown in the middle of a field.

A machine sells for what a buyer pays for an average one of its age and hours, after real auction prices: the hours it has run count as the years a real machine takes to run them. The buyer then takes off the repairs its faults need and what bringing the parts its owner let wear back to an average machine's costs, never more than a full overhaul; parts in better shape add nothing, so an overhaul just before selling never pays for itself. Late in life, a big repair can cost more than the machine is worth, and replacing it becomes the better deal.

## Leasing

A leased machine wears and breaks down like one you own, and its daily care is yours: fluid top-ups, grease, air filter cleaning and the pre-shift check.

Its maintenance is included in the lease, as a rental company has the dealer service its machines: the dealer, or the mobile workshop on the farm, services it free of charge, fluids included. Serviced in your farm workshop, it costs the filters and your own fluids, like any machine. Repairs, inspections, overhauls and repainting are yours to pay.

Returning it charges what the lease does not cover: a maintenance left overdue at the dealer's price, every active breakdown at the dealer's repair price, and washing in proportion to the dirt. The return window lists each charge before you confirm. With Extended Leasing installed, that mod charges the washing and refunds the deposit; the return window shows the deposit refunded and counts it in its total.

## Temperatures

Work and weather set the temperatures of the engine, the oils and the traction battery. There is nothing to set.

- **Overheating calls for a response.** Watch the warnings, ease the load and look after the cooling system: heat wears the machine.
- **An overheating diesel can lose power.** Where thermal protection is available, engine torque falls by `20%` at `110 °C` and half at `115 °C`; cooling back to `112 °C` returns the engine to the first step, and to `107 °C` to full torque. A message announces every change, even with the warnings turned off, and the engine never shuts itself down.
- **Warm-up still matters.** Combustion engines and oils warm up sooner with work, but oil generally takes longer. Avoid heavy work while cold: cold oil adds transmission wear under heavy pulling load, not while idling or sending power only to an implement. High load at suitable engine speed does not by itself count as overload; forcing the engine at very low RPM adds wear progressively.
- **Oil temperature follows the job.** One oil shared by the transmission and the hydraulics has one temperature; separate oils each keep their own.
- **Low fluids weaken cooling.** A clean radiator does not make up for lost coolant or oil: check the levels and top up the circuit that needs it.
- **The fan turns with the engine.** It gives all its air at the engine's rated speed and less below it: a hot engine lugging at low speed, or left at idle, cools less. Machines from before 1997 have a fan bolted on its pulley, with no clutch to fail; from 1997 a viscous clutch drives it, and from 2013 the engine controller, whose fan speed the diagnostic tool reads.
- **A fouled radiator cools less.** The Air Blower cleans it. A **reversible fan**, an option of combustion machines built from `2007`, except cars and trucks, in the shop or at the workshop, blows it out from the cab: `Left Alt + 6` reverses the fan for `15` seconds, the radiators getting no cooling air meanwhile. From `2008`, the fan also reverses on its own every `20` minutes of running, the factory setting of a real reversible fan control. It does not clean the air filter.
- **A stopped machine cools down with the game's time**, sleep included, and its temperatures are kept in the save.

## Drivetrain and Parking Brake

Tractors and other field machines get the drivetrain controls their axles allow; cars and trucks are left as they are. Every machine gets a parking brake.

- **Drive mode** (`Left Alt + 1`): `2WD`, `4WD` or `4WD AUTO`. In AUTO, the front axle engages as soon as the wheels slip or the machine pulls hard below `13 km/h`, and disengages above `20 km/h`. The front axle shows beside the speed dial, in a small round bubble at its top left corner with the drive mode under it; the wheel slip has the same bubble at its bottom left corner, its percentage under it.
- **Differential lock** (`Left Alt + 2`): finds grip where there is none left. It releases by itself above `10 km/h`.
- **Drivetrain stress**: turning on a high-grip surface with the differential lock or the front axle engaged strains the drivetrain and wears the transmission. A warning tells you: release the lock or disengage the front axle before you turn.
- **Parking brake** (`Left Alt + 3`): a new machine is delivered with it applied.
  - Recent CVT and powershift machines, from `2010` on, apply it by themselves when you leave the machine at a standstill, when you stop the engine or after `45` seconds standing still, and release it as soon as you press the throttle. With the engine off, it cannot be released.
  - The others have a hand brake that you apply and release yourself. Leave the machine with the brake released and it may roll down the slope; with the engine off, a manual gearbox left in gear holds it. Drive against the brake and the brakes wear.
  - AI workers release it when they take the machine and apply it when they hand it back.
- **Trip meter** (`Left Alt + 4`): a short press switches the speedometer line between `ODO` and `TRIP`; hold it one second on `TRIP` to reset the trip meter. It is saved with the machine.

With Enhanced Vehicle installed, RMS drives the drivetrain, the parking brake and the odometer: it turns off Enhanced Vehicle's differential, parking brake and odometer functions, and Enhanced Vehicle keeps its guidance and hitch controls. To hand the differentials or the parking brake back, turn off the matching RMS setting, then turn the function back on in the Enhanced Vehicle menu.

## Electrical System

Every machine has the battery, the alternator and the starter of its size and its age, measured on real machines: an 80 hp tractor of 1985 carries 120 Ah and a 50 A alternator, a 300 hp tractor of 2018 carries 210 Ah and 220 A. There is nothing to set.

- **A healthy machine that works looks after itself.** A start is given back to the battery in four to five minutes of running. Up to 80 % the battery takes whatever the alternator can spare; the last fifth comes back slowly, over about five hours.
- **Lights left on with the engine stopped** flatten the battery in three to six hours of game time, sooner on a machine loaded with work lamps.
- **The cold keeps part of the charge out of reach.** A battery needs about 12 % to start at `10 C`, 25 % at `0 C`, 40 % at `-10 C` and more than half at `-18 C`. The charge comes back as the weather warms.
- **The starter no longer rolls dice.** The same situation always takes the same time. It turns slower, with a lower sound, when the voltage drops: cold, a battery running empty or aged, corroded wiring. A cold engine drags it too, its oil thick: on a full battery it turns about `250 rpm` on a mild engine and `150 rpm` at `-19 C`. A diesel needs about `100 rpm` to fire; slower, the starter turns without the engine catching. Insisting drains the battery; when it can no longer turn the engine, the machine says **Battery too weak**.
- **Hold the start key while the engine is slow to start.** An engine colder than `-10 C` or a fault that makes starting hard keeps the starter turning until the engine catches: hold the key, let go and it stops. Otherwise a press starts the engine.
- **Each machine cranks its own starter.** A machine of the base game turns the starter heard in its own engine sound, for as long as the key holds it, and its engine catches as in that sound. Another machine starts with its own engine sound, and while the key holds a slow start it borrows the starter of the base game machine of its kind nearest in power.
- **A failed alternator** leaves the machine running on its battery: two to three hours at night with every light on, four and a half to six and a half by day, while the voltmeter reads the battery instead of `14 V`.
- **Workers switch their lights off** when they stop their engine to wait, and light them again as they leave. Your own lights stay as you set them.
- **Wheel loaders above 110 hp, forestry machines and trucks run 24 V**, like the real ones, on two 12 V batteries of 180 Ah in series. The voltmeter reads `28 V` running and `25.2 V` at rest, the report shows a **24 V Battery**, and with their larger batteries they hold longer: a 250 hp loader keeps its lights on for eight hours with the engine stopped. Jumper cables never link a 12 V machine to a 24 V one.

### Battery disconnect switch

Every machine carries a battery disconnect switch: stand in front of the machine on foot and press `Left Alt + 5`. With the battery disconnected the machine has neither starter nor lights, and its battery only loses a few percent a month on its own. The info box says **Battery disconnected**, and a start attempt tells you to reconnect it. The engine must be stopped to operate the switch. A worker reconnects the battery of the machine it takes.

Left connected, what a parked machine loses depends on its electrics. The durations below are months of the game calendar, at `10 C`:

- **Sound electrics without electronics**, on machines built before 2000, draw nothing: the battery spends the winter on its own.
- **Electronics**, on machines built from 2000 on and on electric machines, keep drawing a little current: the machine no longer starts after three to five months.
- **Worn electrics leak.** The leak appears below two thirds of electrical Condition and grows as it falls: at a third, an old tractor no longer starts after three and a half months and a recent one after two; worn out, two to three weeks are enough.
- **Failing alternator diodes or corroded wiring leak more at each stage**: a month and a half at the first stage, about a week at the last.
- **A worn or sulfated battery also empties faster on its own**, even disconnected: in six months a sound battery loses about a tenth of its charge, the battery of worn-out electrics a quarter, a badly sulfated one four tenths.

### Jumper cables and charger

If a battery is too weak to start, jumper cables link both batteries into one circuit: the donor supports the starter and refills the weak battery while they stay connected. With the cables in hand, the action names what it does to the machine you aim at: **Connect jumper cables**, or **Disconnect jumper cables** on a machine already connected; moving either machine disconnects them.

The **Telwin Doctor Charge 155 Connect on its Diagnostic trolley** costs **800 €** in **Construction > Buildings > Tools**. Push it within **4 m** of a stationary RMS vehicle belonging to your farm, stop its engine, and use **Connect charger** on foot. Choose **Charge the battery** or **Starting aid**, then select the vehicle if several are in reach. Left alone, the trolley holds in place as if its casters were locked: walking into it neither moves nor tips it, and it rolls again as soon as you push it.

- **Charge the battery** gives the charger's full 150 A, within what the battery takes: an empty battery is back to 80 % in 40 minutes to a little over an hour of game time depending on its size. A 24 V machine takes the 80 A the charger gives at 24 V: 80 % in 1 h 48.
- The charge then finishes slowly: the last fifth takes about five hours. A healthy battery takes this current without harm; the charger lowers it on its own as the battery fills.

Charging continues while you work elsewhere, follows the game's time speed and resumes after loading the save; no charging takes place while the game is closed. Disconnect before starting, or reconnect for **Starting aid**. Like the real charger, START works on 12 V machines only. In START, the charger supplies up to 200 A only while the starter turns; once the engine runs, it supplies no current and prompts you to disconnect. Wait 30 real seconds between attempts. Starting aid does not guarantee a successful start: on a flat battery, charge for a few minutes first, as Telwin recommends. It does not repair battery faults or wear.

The HUD and charger display use the same circuit voltage as the vehicle HUD, together with battery level and actual delivered current. As on the real charger, its display shows the nominal 12 or 24 V of the machine and the process: the starting aid alone, or the Pulse-Tronic charge with its phase, 4 up to 80 %, 5 up to 100 %, 7 holding the charge. Notifications confirm the connected vehicle, disconnection, completion and interruptions. Use **Disconnect charger** at any time, including after a full charge. Moving the trolley within 4 m does not interrupt the connection. Moving the connected vehicle, workshop work, leaving range or an invalid connection disconnects it and clears the old readings. A charger and jumper cables cannot be connected together.

The intermediate shelf has separate spaces for a grease gun and an air blower bought by your farm, and the bottom shelf takes the jumper cables, coiled flat. Within about a metre of the trolley, on any side, the green outline of each empty space shows where its tool goes: with the tool in hand, the activate key puts it down. Jumper cables put away come off the machines they were clamped on. With empty hands, look at a stored tool and the same key takes it back. The tools stay on the trolley when you move it.

### Diagnostic tool

The trolley takes a **Jaltest AGV diagnostic tool** as an option: a rugged laptop open on its top shelf, with the multibrand agricultural software. Choose **Yes** for the diagnostic tool when you buy the trolley, in the shop or in **Construction > Buildings > Tools**, for **4 880 €** in all, or add the tool to a trolley you own with **Configure** at the workshop for **4 080 €**, the price of the real kit. The first year of the software licence comes with the kit, and the bottom bar of the software gives the month it ends. Expired, the software still reads the fault codes but no longer gives their technical information (part at fault, repair time, where to repair it), as a multibrand Jaltest does; **Renew license** in that bar buys a new year, **595 €** scaled to the Economic Difficulty.

On foot near a trolley carrying the tool, look at the laptop: the action becomes **Use diagnostic tool** and opens the software full screen, at the mouse or the controller. Around the trolley, the key opens the laptop you look at, puts away the tool in your hand, takes the stored tool you look at with empty hands, and otherwise works the charger. The tool needs no charger. The software has two pages:

- **Connection** lists the machines of your farm within **4 m** of the trolley, each with why the tool can or cannot be plugged into it: the machine stands still, and it carries a controller (a combustion machine that uses AdBlue or was built from 2000, or an electric). Select one and click **Connect**: the scan starts at once, and the screen of the laptop lights while it is plugged in. One tool per machine; the charger of the same trolley can be connected at the same time.
- **All Systems Scan** reads the controllers of the machine one after the other, in about two minutes. The technician switches the ignition on: the engine may stay stopped, only the battery of the machine must not be disconnected at its switch. Each controller lists the fault codes it stores, as the real standard writes them (SPN and FMI, with their wording): engine, transmission (powershift or variable gearbox), central computer (hydraulics, power take-off, brakes), dashboard, and on an electric its inverter, traction battery, converter and charger. A fault stores its code once it lights its warning light; the failure mode follows the colour of the light. A part no sensor watches stores no code: the dashboard shows its lit light without a code.
- The code you select is explained beside the list. For a fault only the tool locates, electronic or high voltage, it names the part, its repair time and where it can be repaired. For any other, it names the system: the code says what the machine measures, an inspection finds the part.

The reading is free and goes to the maintenance log of the machine. With the tool plugged into the machine, the mobile and personal workshops run Standard and Complete inspections on machines with a controller, read the fault codes during a maintenance and repair the electronics; without it they refuse that work and say to connect it. A mobile workshop still refuses heavy dismantling, high voltage and overhauls.

Diesel preheating starts automatically below `25 C`. It remains short in mild weather and lengthens progressively as the engine gets colder. At `5 C` and above, failed glow plugs can make the start rough but do not block it solely because of preheating; below that point, their condition becomes start-critical.

## Electric Vehicles

An electric machine is tracked like any other, with the parts it really has: an electric motor in place of the engine, a traction battery in place of the fuel system, and power electronics in the electrical system. It keeps its auxiliary battery, in 12 or 24 V like the machines of its family, its cooling circuit, its reduction gear or gearbox, its hydraulics and its chassis.

- **The traction battery ages.** It holds less energy as it wears, down to four fifths of its capacity at the end of its life. Deep discharges, a heavy sustained draw and heat age it faster. The gauge, the charging station and the report all read the capacity it has left, in kWh, and the workshop restores it.
- **Cold costs range, power and charging speed.** Below `10 °C` the pack gives less: a fifth of the range is gone below freezing and half below `-20 °C`, with less power to match. A cold pack also charges slower, at half the station's power at `0 °C` and a fifth at `-10 °C`, and you only pay for the energy received.
- **Heat follows work and charging.** The drive cooling circuit and traction pack keep separate temperatures. Work warms both; charging heat follows the energy the pack actually receives. Hot operation raises wear and lights the warnings; heat alone never cuts the power or stops the machine.
- **The auxiliary battery still matters.** A converter charges it while the machine is on or plugged in. Flat, the machine will not wake up even with a full traction battery. Jumper cables and the charger both work; an electric can receive a jump start but never gives one.
- **Only the fluids it carries.** An electric has no engine-oil service. Its gearbox, hydraulic oil and coolant keep their own deadlines; no visit is added for an absent circuit. Late service wears only the systems supplied by the overdue fluid.
- **Its own wear and failures.** The motor, traction battery and reducer respond to their own operating limits. Low RPM does not add lugging wear to an electric reducer.
- **Its own dashboard lamps.** The engine lamp turns amber then red on a drive fault. A turtle lights when a cold pack limits the machine's power. A battery lamp beside the warning triangle watches the traction battery, blue when the pack is cold, and the auxiliary battery keeps its own lamp. There is no oil lamp and no glow lamp.

## Installation

1. Place the mod ZIP file into your FS25 `mods/` directory (do not extract).
2. Activate the mod in mod selection.
3. Access RMS from the fleet menu (`P` key), the in-game settings, and workshop interactions.

> **Note:** RMS raises the game's limit of 255 fill types to 511. Large maps and long mod lists then keep the products of every mod.

> **Important:** Do not run RMS and Advanced Damage System together. RMS steps aside when it finds ADS and leaves it in charge, so nothing runs twice.

## Usage

### Running a service

1. Take the vehicle to a workshop. Available services depend on the workshop type.
2. To repair a fault the dashboard or the pre-shift check shows, have it identified first by an `Inspection`, or by the `Maintenance` if one is due, which looks for faults too. Then choose the needed service, including `Top up` or `Repainting`.
3. Review the available options, price and duration before starting.
4. Read the report afterwards when the procedure provides one. The maintenance log keeps every past procedure.

### Reading the warning signs

1. Watch the dashboard indicators, which generally light from stage 2 on modern vehicles; some faults can light them earlier.
2. Listen for knocking, whistling, and grinding, and read the exhaust: black means the engine is choking on fuel it cannot burn, blue means it is burning oil, white means fuel is leaving the engine unburnt. Most stage 1 faults otherwise have no dashboard warning.
3. Run a pre-shift check when something feels off, then an inspection, or the maintenance due, to identify the fault.
4. Repair early. Left to grow, a fault damages other parts and the bill grows with them, while its symptoms get worse.

### Leaving a machine out of RMS

1. Open the fleet menu (`P` key) and select `Mechanical Dashboard`.
2. In `Equipment fleet`, open a category or `All equipment`, highlight the machine and press `X` (`Exclude from RMS`): RMS stops tracking its wear.
3. Go back to `Equipment fleet` with the button under the list, open `Untracked equipment` in its place and pick a category: each machine states why it is left out, and `X` (`Include in RMS`) brings a supported machine back in. A machine that was never tracked starts from its resale value, like a used one.
4. On a server, only an admin can make this choice, and a machine under a workshop procedure cannot be excluded until it is done.

## Debug Window

`Debug Mode` in the RMS settings shows a window across the screen while you drive a machine RMS tracks: its systems and their parts with their wear and chance of failing, what wears it right now and why, its faults and what comes next, the work in progress, and every reading of the machine, from temperatures and fluids to the battery and the drivetrain. `Alt Gr + F5` (`Ctrl + Right Alt + F5`), which can be reassigned in the controls, opens and closes it too. In multiplayer only admins see it, each opening and closing their own, the server sending the reading twice a second while it is open. Its texts are in English only.

## Console Commands

For testing and debugging. Unless noted, a command acts on the vehicle you sit in, which RMS must track. On a server the commands run on the server: only an admin can use them, and the answer comes back to that admin's console. `rms_exhaustOverride` only changes what your own screen shows.

| Command | Description |
| --- | --- |
| `rms_listBreakdowns` | Lists every breakdown ID in the registry, with the number of ways a part fails in when it has several; works outside a vehicle |
| `rms_addBreakdown [id] [stage] [way]` | Adds a breakdown at stage 1 or at the given stage, on a random part of the machine without an ID. It arrives unidentified, as in play: the workshop lists it once an inspection or a maintenance has found it. A part that fails in several ways takes the given way, or one at random; `rms_listBreakdowns` tells how many ways each has. A filter breakdown clogs its filter to that stage |
| `rms_removeBreakdown [id]` | Removes one breakdown, or all of them without an ID; removing a filter breakdown fits a new filter |
| `rms_advanceBreakdown [id] [stage\|reverse]` | Advances one breakdown, selects an existing stage or steps back; without an ID, advances all where possible |
| `rms_setCondition <0.0-1.0>` | Sets Condition on every enabled system, every part worn alike |
| `rms_setSystemCondition <system> <0.0-1.0>` | Sets Condition on one system, its parts worn alike |
| `rms_setPartWear <id> <wear>` | Sets the wear of one part of the vehicle, named by its breakdown ID: `1.0` is a whole machine life, more is allowed. Prints the risk of the part against that of a new one; the next draw starts from the wear set. An unknown ID lists the parts of the vehicle |
| `rms_setService [0.0-1.0] [engine\|transmission\|hydraulic\|coolant]` | Sets how much of its hours a service clock has left: `1.0` just serviced, `0` used up. Sets the four clocks without a clock name; defaults to `1.0`. The dates of the last services do not change |
| `rms_setPaintWear <0.0-1.0>` | Sets the paint wear a Repainting order repairs |
| `rms_setDirtAmount <0.0-1.0>` | Sets the dirt level |
| `rms_setFuelLevel <value>` | Sets fuel or electric traction charge: values from `0` to `1` are fractions, values above `1` to `100` are percentages |
| `rms_reinitializeVehicle` | Seeds the vehicle again as a used machine of its hours, as when RMS first met it: each part worn by those hours and the care of its previous owner (`careful`, `regular` or `neglected`, by default the one its repair need tells), the parts that failed replaced, service clocks where the owner left them, and a neglectful owner's breakdowns since his last service; unavailable during a workshop procedure |
| `rms_reinitializeFluidCapacities` | Recomputes physical fluid capacities for the current vehicle, keeping its litres |
| `rms_resetFactorStats` | Restarts the wear statistics: the wear shares of the debug window and the wear block of inspection reports read them. Also restarts the collision and PTO engagement counts |
| `rms_getServiceState` | Prints workshop and service state: procedure, timers, options, service clocks and dates, queues |
| `rms_showServiceLog [index]` | Prints the service log, or one entry in detail using its integer index |
| `rms_getDebugVehicleInfo [1]` | Prints how RMS reads the vehicle: brand, type, category, electrical circuit and transmission; lists its specializations when given `1` |
| `rms_exhaustOverride <opacity\|-> [flow\|-] [vapour\|-]` | Overrides exhaust rendering locally for all machines; `-` keeps each engine's value and `off` clears the override |
| `rms_setSpecVar <path> <value>` | Sets one value of the vehicle's RMS state, see the paths below; displayed oil temperatures, the Condition of the vehicle and of each system, and circuit voltage are calculated and cannot be set |
| `rms_printSpecVar <path>` | Prints a value of the vehicle's RMS state, or a whole table when the path names one |

### Useful paths for `rms_setSpecVar`

| Path | Value |
| --- | --- |
| `batterySoc` | Battery charge, from `0` to `1` |
| `engineOilLevel`, `coolantLevel`, `transmissionOilLevel`, `hydraulicFluidLevel` | Fluid level as a share of the circuit's capacity, from `0` to `1`; with a common sump the hydraulic oil follows `transmissionOilLevel` |
| `lubricationLevel` | Grease, from `0` to `1` |
| `radiatorClogging`, `airFilterClogging`, `fuelFilterClogging`, `hydraulicFilterClogging` | Clogging, from `0` to `1` |
| `serviceCalendar.engine`, `.transmission`, `.hydraulic`, `.coolant` | Age of the machine, in months, at the last service of that clock; a low value on an old machine makes the service due by date |
| `activeBreakdowns.<ID>.isVisible` | `true` identifies a breakdown as an inspection would, `false` hides it again |
| `rawEngineTemperature`, `rawTransmissionTemperature`, `rawHydraulicTemperature` | Temperatures in °C, see the temperature test commands |

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

This applies to commands such as `rms_setSystemCondition`.

Examples: `rms_setSystemCondition engine 0.75`, `rms_setPartWear OIL_PUMP_MALFUNCTION 0.9`.

### Temperature test commands

The thermal model remains automatic. Console forcing changes the current physical state for testing; normal heating and cooling continue afterwards.

```text
rms_setSpecVar rawEngineTemperature 90
rms_setSpecVar rawTransmissionTemperature 90
rms_printSpecVar rawTransmissionTemperature
```

Engine temperature writes use the shared native motor state. Transmission oil uses `rawTransmissionTemperature`; the dashboard value `transmissionTemperature` is smoothed and cannot be written directly. For a separate hydraulic oil circuit, use `rawHydraulicTemperature`. With a common sump, transmission and hydraulic oil share the transmission temperature.

## Changelog

### v1.0.0.0-beta.1

- Reworked machine production years, which set each machine's period equipment such as the particulate filter, LED lights, the reversible fan and dashboard lamps
- Added the model launch year to the shop
- Added engine oil change intervals that follow the machine's era: older machines need it more often
- Reworked the settings page, which now opens without freezing and describes each setting more clearly
- Fixed AI workers, Courseplay and AutoDrive wearing the machine by working it cold, hitting obstacles or spinning their wheels on the spot
- Fixed breakdowns of lamps missing from the machine, such as a beacon not chosen in the shop
- Fixed the most powerful Stage V machines, such as large combines, having no particulate filter
- Fixed machines bought in another colour without paying for the paint: any colour other than the one already selected now costs a full repaint
- Fixed the vehicle configurator changing an owned machine's colours without charging the repaint: colours now change only through a full repaint

### v0.13.0.1

- Fixed the game freezing while loading a savegame with some mods that switch a machine's lights

### v0.13.0.0

- Reworked breakdowns to follow the wear of individual parts, with gradually worsening symptoms
- Added particulate filter regeneration and AdBlue faults on modern diesel engines
- Reworked cooling and added an optional reversible fan for radiator cleaning
- Reworked hydraulic wear to account for the weight being lifted
- Added previous maintenance history to used machines in the shop
- Reworked resale values based on age, operating hours and mechanical condition
- Reworked repair and fluid prices
- Improved identification of fluid cans and drums by product in the game
- Reworked the warranty: 24 months, extensions at purchase and 12-month cover for dealer-fitted parts
- Removed Premium parts; original parts are no longer defective, and aftermarket and used parts are defective far less often
- Added the origin of used parts: the repair card shows the hours of the machine they come from, which sets their wear, and a 3-month warranty on the part
- Improved the RMS menus, dashboard and inspection reports
- Added a diagnostic tool for reading fault codes, available as an option on the Telwin trolley
- Reworked breakdown messages to suit the machine's onboard equipment
- Removed fuel and hydraulic filters from the pre-shift check
- Changed mobile and farm workshops to require the diagnostic tool for electronic work
- Reworked Debug Mode
- Reworked the models of the air blower, grease gun, jumper cables and charger trolley
- Reworked battery charging to follow the current the battery accepts
- Added tool storage on the charger trolley
- Reworked breakdown sounds
- Reduced engine oil consumption on healthy engines
- Fixed RMS menus taking the colours of mods that recolour the HUD
- Fixed machines sold in multiplayer returning to the used offers without their faults and wear
- Fixed the player falling behind the charger trolley while pushing it
- Fixed the hydraulics wearing and heating up while a header follows the ground on its own
- Fixed faults remaining on a part a machine no longer has after changing its configuration
- Fixed the PTO and steering wearing faster when an AI worker engages the PTO at high revs or steers at a crawl
- Fixed petrol engines asking for preheating

### v0.12.0.0

- Simplified the reliability and ease of maintenance ratings
- Renamed the maintenance levels after their interval in hours and added deadlines in hours or months
- Vehicle service intervals now follow the Maintenance spacing setting
- Repair time and labour costs now depend on the work and its access
- Mobile workshop restrictions now depend on the selected work, with reasons shown for refusals
- Improved the RMS screens: reworked Mechanical Dashboard, side-by-side work orders with a detailed quote, wear in the inspection report
- Reworked engine and oil temperatures
- Reworked wear under heavy load: reduced during normal driving and progressive at low RPM
- Changed engine overheating protection to reduce power in two steps
- Removed manual temperature settings
- RMS settings are now saved only in the current savegame
- Added support for electric vehicles
- Added an odometer with a resettable trip meter
- Reworked the parking brake and its sounds: automatic or manual depending on the machine, without a global setting
- Removed the Drivetrain Stress Damage setting; damage still applies
- Changed Enhanced Vehicle compatibility: RMS now manages the drivetrain, parking brake and odometer
- Improved damaged steering behavior
- Added chassis damage from collisions
- Changed chassis, electrical and hydraulic wear on rough ground
- Fixed excessive chassis wear when manoeuvring at low speed with the wheels turned
- Reworked batteries, alternators and starters to match each machine's 12 or 24 V system
- Removed manual battery and alternator settings
- Changed hard starts and starter sounds: an emptying battery and a cold engine slow the starter, and a diesel cranked too slowly no longer fires
- Added a battery disconnect switch for vehicle storage
- Changed the charger: automatic charging, fast charging and starting aid
- Fixed worker lights staying on while waiting with the engine stopped
- Added fluid cans poured by hand into the machine you aim at, with a level gauge and sounds
- Changed the workshop Top up: now at the dealer only, fluid cans do it on the farm
- Fixed fluid transfers refused at the ends of long machines
- Added a battery drum pump: fit it on a 200 L drum and fill machines through its nozzle and hose
- Removed battery recharging from workshop services; use the charger
- Added fuel and hydraulic filter clogging: faster on the fuel reserve or under hydraulic work, new filters at every service
- Changed the visual inspection and mobile maintenance: they no longer find electronic faults, which need a diagnostic tool
- Removed labour costs from maintenance in the farm workshop: you pay the filters and use your own fluids
- Changed the last maintenance level: valve, injector and thermostat checks now relieve the engine, fuel system and cooling only
- Removed the Reset Fleet button; a Vehicle Lifespan change applies from then on and vehicles keep their condition
- Added maintenance included in the lease: the dealer and the mobile workshop service a leased vehicle free of charge; with Extended Leasing the return window shows the deposit refunded
- Changed engine oil consumption to that of real diesels: a healthy engine worked hard needs a top up late in its service interval, a worn one far more often; the oil lamp now lights only when the oil runs critically low
- Raised the game's limit of 255 fill types to 511: large maps and long mod lists keep all their products
- Fixed fluid cans and drums coming out of a bale and pallet storage full, and drums shown as 5 L cans to players on a server
- Fixed 200 L drums standing above the ground and above the forks of a forklift

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
