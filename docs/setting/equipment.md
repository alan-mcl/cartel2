# Equipment and components

**Status:** Full component taxonomy is **setting intent** from original design spreadsheet and notes. The Godot prototype JSON includes seven chassis, fourteen ship templates, forty-eight branded propulsion SKUs (five commercial engine types plus one gravitic placeholder), power plants, compute cores, life support, sensors, lasers, mass drivers, plasma/scatter/missile weapons, cargo/fuel modules, armour, and an alpha hyperdrive catalog entry (no translation gameplay). **Light laser and mass driver fire in orbital flight**; shields remain design-only.

## Design layers

| Layer | Authority | Notes |
|-------|-----------|-------|
| **Full component model** | Original design spreadsheet | Stats for chassis, engines, weapons, shields, armour, LSS, hyperdrives, ammo |
| **Ship families** | Ships design doc | Lore and intended loadouts — see [ships.md](ships.md) |
| **Prototype catalog** | `data/catalog/*.json` | Chassis, unified modules, ammunition types, ship templates |

Rebuild should treat the spreadsheet as **target balance**; JSON as **current instance data**.

## Space ship slots

```
Chassis (required, fixed on owned ships)
Installed modules[] (slot → module_id)
  ├── propulsion (main_engine mount)
  ├── power (power mount)
  ├── systems (system mount): computer, life support, sensors, …
  ├── weapons (light/medium/heavy weapon mounts)
  └── other: cargo bays, fuel tanks, armour, magazines
```

Mount counts come from chassis `mounts`. Unused mounts are normal.

---

## Chassis

| Stat | Description |
|------|-------------|
| Weight | Hull structural mass (`mass` in JSON) |
| Mass limit | Maximum configured ship mass |
| Volume | Internal volume envelope |
| Hits | Structural integrity |
| Maneuver | low / medium / high — affects rotation and damping |
| Mounts | Available hardpoints by category |

### In prototype JSON

| id | Maker | Maneuver | Notes |
|----|-------|----------|-------|
| `flare_on_chassis` | Holt-Winters | high | Light sporty hull |
| `pegasus_chassis` | GVW Corp | low | Workhorse freighter |
| `krypton_chassis` | Durbin-Watson Corp | high | Mid-range saucer |
| `wolff_chassis` | Bayes Inc | medium | Armed freighter / gunship |
| `dragon_chassis` | Kolmogorov-Smirnov | high | Interceptor |
| `juno_chassis` | Bayes Inc | medium | Light scout |
| `silhouette_chassis` | Oklahoma Combine | high | Tactical fighter |

Each chassis has a **list price** (`cost` in JSON) for sale at **Skyedge Space Ships** on Proxima Habitat. Unfitted frames must be outfitted at the Workshop before they can undock.

Each chassis references a hull **sprite** path and **hull_color** for rendering.

---

## Modules (`modules.json`)

All equipment is defined in a single catalogue, filtered by `category`.

### Propulsion (`category: propulsion`, mount: `main_engine`)

Commercial main engines are branded products: **maker** (corporation), **brand** (propulsion marque), marketing **name**, and **`engine_type`** (technology class). Progression is expressed in stats and price, not Mark numbers.

| Stat | JSON field | Prototype use |
|------|------------|---------------|
| Weight | `mass` | Ship mass |
| Thrust | `thrust` | Forward acceleration |
| Max speed | `max_speed` | Speed cap km/s |
| Fuel use | `fuel_consumption` | Consumed in flight (shared pool today — see [backlog](../design/backlog.md)) |
| Boost | `boost_multiplier` | Boost speed factor |
| Power | `power_demand` | Operating budget |
| Type | `engine_type` | Technology class (see below) |

Manufacturer tiers for propulsion are defined in [manufacturers.txt](../design/manufacturers.txt). The habitat workshop sells the full catalogue; no per-world stock filter yet.

#### Engine types

Five types are in the commercial catalog today. All share the same fitting rules; type drives stats, marketing, and future mechanics. **Gravitic** is reserved as a single placeholder SKU (Flare-ON SK); Integrated Sail is not catalogued yet.

| Type | Role | Typical profile |
|------|------|-----------------|
| **Chemical** | High thrust, poor fuel efficiency, low power draw. Cheap and mature — dock tugs, budget scouts, emergency burn. | High thrust, moderate speed, strong boost, thirsty fuel |
| **Hydro-thermal** | Heats hydrogen and expels exhaust. Better fuel than chemical while retaining substantial thrust; **hungry for ship power**. Mature everyday engine. | Balanced thrust/speed, moderate fuel, high `power_demand` |
| **Electric plasma** | Ship power drives plasma exhaust. Extremely fuel-efficient, suited to sustained cruise; **capped by plant MW**. | Lower thrust, high `max_speed`, weak boost, very low fuel |
| **Direct fusion** | Dedicated fusion reactor in the engine; charged products through a magnetic nozzle. High performance, little reaction mass; heavier and costlier. | High thrust/speed, low ship power draw, low fuel burn |
| **Antimatter** | Matter–antimatter annihilation. Elite thrust and speed; engine list price is extreme. **Fuel type differentiation** (expensive antimatter stores) is deferred — see [backlog](../design/backlog.md). | Top thrust/speed/boost, tiny fuel use on shared pool |
| **Gravitic** | Placeholder only — not a filled product line. | Near-orbit performance (mechanics TBD) |

Propulsion marques are **distinct from** power/compute/life-support brands (e.g. Sundancer for HW engines vs Helios for plants and LSS).

#### In prototype JSON

Forty-eight branded SKUs across nineteen manufacturers (~12 chemical, ~16 hydro-thermal, ~8 electric plasma, ~7 direct fusion, ~4 antimatter, 1 gravitic). Examples:

| id | Maker | Brand | Type | Notes |
|----|-------|-------|------|-------|
| `gi_ht_18` | General Industrial | GI | hydro_thermal | Pegasus P101/P103 default |
| `hw_sundancer_compact` | Holt-Winters Corp | Sundancer | direct_fusion | Flare-ON SS |
| `hw_sundancer_loft` | Holt-Winters Corp | Sundancer | gravitic | Flare-ON SK placeholder |
| `ora_bellatrix_trace` | Orion Aerospace | Bellatrix | antimatter | Krypton K3 |
| `prv_ionique_annihilon` | ParaRamcoVidia | Ionique | antimatter | Glossy law-enforcement tier |

`ShipAssembler` derives `ShipStats` from loaded mass; `ShipOperations` ticks fuel, power, and compute in flight.

### Power plants (`category: power`, mount: `power`)

Shipboard reactors mount on the chassis `power` hardpoint. One plant is typical; larger hulls may carry more in future designs.

| Stat | JSON field | Prototype use |
|------|------------|---------------|
| Output | `power_generation` | Operating budget (MW) |
| Weight | `mass` | Ship mass |
| Envelope | `volume` | Fitting limit |
| Fuel burn | `fuel_consumption` | Plant fuel use in flight |
| Maker | `maker` | Corporation — see [corporations.md](corporations.md) |
| Brand | `brand` | Product family / marque within the maker |
| Type | `plant_type` | Technology class (see below) |

Manufacturer tiers for power plants are defined in [manufacturers.txt](../design/manufacturers.txt). The habitat workshop sells the full catalogue; no per-world stock filter yet.

#### Plant types

Three types are in the catalog today. All share the same fitting and operating rules in the prototype; type drives stats, marketing, and future mechanics.

| Type | Role | Typical output | Fuel |
|------|------|----------------|------|
| **Fission** | Mature, compact, reliable. Default for older, cheaper, smaller, and frontier ships. | 16–72 MW | Moderate |
| **Fusion** | Newer, advanced. Higher output and better fuel burn at a premium. Sporty and refitted hulls. | 28–54 MW | Lower |
| **Radioisotope** | Decay heat; always on, no refuelling. Low power — life support, beacon, sensors only on light hulls. | 6–12 MW | Zero |

Reserved for later (no SKUs yet): **solar**, **chemical** — may ignore ship fuel or gate on environment.

#### In prototype JSON

Forty-eight branded SKUs across nineteen manufacturers (~31 fission, ~11 fusion, 6 radioisotope). Examples:

| id | Maker | Brand | Type | Output |
|----|-------|-------|------|--------|
| `gi_pp_18` | General Industrial | GI | fission | 18 MW |
| `hw_helios_compact_40` | Holt-Winters Corp | Helios | fusion | 32 MW |
| `ora_ap_56` | Orion Aerospace | Orion | fusion | 54 MW |
| `hw_helios_ember` | Holt-Winters Corp | Helios | radioisotope | 9 MW |

Ship templates: older workhorses (Pegasus, Juno, Krypton K2, Silhouette) carry fission; Holt-Winters Flare-ON and late refits carry fusion. No template defaults to a radioisotope plant.

The POC `fusion_plant_mk1` / `fusion_plant_mk2` Bayes Inc placeholders are retired.

### Compute cores (`category: computer`, mount: `system`)

Shipboard compute cores mount on the chassis `system` hardpoint. One core is typical; larger hulls may carry more in future designs.

| Stat | JSON field | Prototype use |
|------|------------|---------------|
| Capacity | `compute_capacity` | Operating budget (CU) |
| Weight | `mass` | Ship mass |
| Envelope | `volume` | Fitting limit |
| Power | `power_demand` | Operating budget (MW) |
| Maker | `maker` | Corporation — see [corporations.md](corporations.md) |
| Brand | `brand` | Product family / marque within the maker |
| Type | `core_type` | Technology class (see below) |

Manufacturer tiers for compute cores are defined in [manufacturers.txt](../design/manufacturers.txt). The habitat workshop sells the full catalogue; no per-world stock filter yet.

**Role:** cores **only supply compute (CU)** in the prototype. Targeting, fire-control, extra HUD features, and similar functions will be **separate system modules** that consume CU and grant capabilities. Every core still carries `basic_hud` so undocked ships show flight instruments — a temporary gate, not a product role.

#### Core types

Three types are in the catalog today. All share the same fitting and operating rules in the prototype; type drives stats, marketing, and future mechanics.

| Type | Role | Typical CU | Notes |
|------|------|------------|-------|
| **Silicon** | Conventional semiconductor computing. Cheap, mature, robust, ubiquitous. | 8–28 | Default for older, cheaper, and frontier ships. Best CU per credit. |
| **Photon** | Photonic computing — light for computation and data movement. Excellent bandwidth for parallel workloads. | 22–48 | Attractive for sensor-heavy, communications, and sporty hulls. Best CU per tonne and watt. |
| **Quantum** | Quantum computing — specialized, not simply faster. Useful for particular mathematical, optimization, cryptographic, and simulation workloads; poor as a general-purpose ship computer. | 10–20 | Expensive, delicate, poor CU per credit. **No template defaults to quantum.** Future: may grant specialist capabilities (crypto, optimization, simulation) in addition to CU. |

#### In prototype JSON

Forty-one branded SKUs across sixteen manufacturers (~27 silicon, ~9 photon, 5 quantum). Examples:

| id | Maker | Brand | Type | CU |
|----|-------|-------|------|-----|
| `mdc_monday_core` | Monday Corporation | Monday | silicon | 12 |
| `hw_helios_prism` | Holt-Winters Corp | Helios | photon | 38 |
| `prv_qbit_foundry` | ParaRamcoVidia | PRV | quantum | 12 |
| `sne_lattice` | SnedeCorp | SnedOS | photon | 36 |

Ship templates: workhorses and budget hulls carry silicon; sporty and late refits carry photon. No template defaults to a quantum core.

SnedeCorp is the galactic software monopoly in lore, but still sells **sealed, attested hardware** — the box SnedOS runs on. ParaRamcoVidia is the glossy semiconductor house.

The POC `nav_combat_core_mk1`, `nav_combat_core_mk2`, and `targeting_core_mk2` placeholders are retired. Targeting will return as a CU-consuming system module, not a core.

### Sensor (`category: sensor`, mount: `system`)

| id | Capabilities | Notes |
|----|--------------|-------|
| `sensor_basic` | `local_sensor`, `local_system_waypoints`, `sensor_read_beacons`, `4_space_topology` | Local radar panel; edge arrows; transponder label overlay; 4-space exit portal labelling |
| `sensor_advanced` | same as basic | Extended-range sensors |

### Transponder (`category: transponder`, mount: `system`)

| id | Notes |
|----|-------|
| `vessel_registration_beacon` | Commercial Article 19 identification transmitter. Required in-system. Broadcasts registration + pilot callsign when powered (~0.3 MW). Sold at the Habitat Workshop (Transponder tab). |

**Article 19 (Commercial):** vessels operating in-system must carry an activated Vessel Registration Beacon broadcasting hull registration and pilot callsign. Ship name and corporate affiliation are optional broadcast fields (affiliation is NPC-only in the prototype). Player identity is shown on hover only; other vessels and landmarks appear via `sensor_read_beacons` overlay.

---

## Armour

Design materials: **5–15 mm Titanium / Endosteel** with hit points.

In the module model, armour is an **internal module** (`category: armour`) adding `hits` to the assembled hull pool.

### In prototype JSON

| id | Maker | Mass | Hits |
|----|-------|------|------|
| `chitanium_5mm` | Bayes Inc | 0.8 t | 12 |

---

## Shields (design only)

Energy, missile, and deflector shield tiers with hit pools and damage-type stopping rules. No shield objects in prototype JSON.

Holt-Winters holds major market share for shield generators in corporate lore.

---

## Hyperdrives (catalog placeholder)

| Class | Module id | Notes |
|-------|-----------|-------|
| Alpha | `hyperdrive_alpha` | Dragon Gold template; no translation gameplay yet |

**Future Unspace role:** hyperdrive-equipped ships will be able to initiate translation from 4-space without reaching a fixed exit portal, and eventually from regions away from jump-gate entry points. Jump gates remain the standard shallow-route injection method for ships without hyperdrives.

---

### Life support (`category: life_support`, mount: `system`)

Shipboard life support systems mount on the chassis `system` hardpoint. One unit is typical; larger hulls may carry more in future designs.

**Volume is cabin + recyclers**, not a rack. Fitting a life-support SKU is fitting the seats or bunks, ablution, aisles, and air plant into the chassis envelope.

| Stat | JSON field | Prototype use |
|------|------------|---------------|
| Capacity | `life_support_capacity` | Crew the ship can sustain (people), 1–6 |
| Weight | `mass` | Ship mass (furnishings and recyclers, not empty cubic metres) |
| Envelope | `volume` | Cabin + plant, counted against chassis `volume` |
| Power | `power_demand` | Operating budget (MW) |
| Compute | `compute_demand` | Operating budget (CU) |
| Maker | `maker` | Corporation — see [corporations.md](corporations.md) |
| Brand | `brand` | Product family / marque within the maker |

Manufacturer tiers for life support are defined in [manufacturers.txt](../design/manufacturers.txt). The habitat workshop sells the full catalogue; no per-world stock filter yet.

**Role:** life support **sustains crew** in the prototype. Launch requires installed life support with capacity ≥ occupant count (currently 1). Cabin mode and luxury are optional **capability flags** — not a type enum.

#### Transport vs habitat

| Flag | Mode | Analog |
|------|------|--------|
| (none) | **Transport** | Commercial air travel: seating and ablution. You sit the hop; you do not live aboard. |
| `ls_habitat` | **Habitat** | Cruise cabin or long-haul truck sleeper: at least a shared bunk. You can sleep and linger. |

Do not add `ls_transport`. Workshop stock still labels the implied default as Transport vs Habitat.

Fighters, cockpit packs, and short-haul scouts are transport. Freighters, gunships, and live-aboard yachts are habitat.

#### Luxury flags (future hooks)

Original design tiers A1–A4 map onto capacity plus optional flags. A5 (bar) is reserved for later. Luxury stacks with habitat: transport + luxury is first-class seats; habitat with no luxury is a hot bunk or truck sleeper; habitat + luxury is cabin hospitality.

| Flag | Original tier | Meaning |
|------|---------------|---------|
| (none) | A1 | Spartan. Recyclers and seats or bunks. |
| `ls_comfort` | A2 | Climate, decent air, proper seats or bunks. |
| `ls_luxury` | A3–A4 | Cabin-grade hospitality. |

Spartan SKUs omit luxury flags. Flags are install-only hooks; no luxury gameplay in the prototype yet.

#### Volume floors (m³ per person)

| Mode | Spartan | Comfort | Luxury |
|------|---------|---------|--------|
| Transport | 2.5 | 5 | 7 |
| Habitat | 8 | 11 | 14 |

1-seater **transport** cockpits still need ~4–6 m³ (controls, seat, ablution), not 2.5. 1-seater **habitat** (truck sleeper) is ~8–14 m³.

Current chassis envelopes are unchanged (Flare-ON 24 m³ through Pegasus 60 m³). Habitat at these floors eats hull volume: a 4-person live-aboard fits a stock Pegasus as spartan bunks; 2-person habitat is the practical cap on Krypton, Wolff, and Dragon. Industrial 6-person spartan habitats (~48 m³) are catalogue-only until larger hulls exist.

#### In prototype JSON

Forty-one branded SKUs across fifteen manufacturers. Crew is 1, 2, 4, or 6. Examples:

| id | Maker | Brand | Crew | Mode | Flags |
|----|-------|-------|------|------|-------|
| `te_handy_air` | Tukey Enterprises | HandyAir | 1 | Transport | — |
| `hw_helios_breath` | Holt-Winters Corp | Helios | 1 | Transport | `ls_comfort` |
| `hw_helios_lounge` | Holt-Winters Corp | Helios | 1 | Habitat | `ls_habitat`, `ls_luxury` |
| `gi_ls_4` | General Industrial | GI | 4 | Habitat | `ls_habitat` |
| `prv_vitacore_l` | ParaRamcoVidia | VitaCore | 2 | Habitat | `ls_habitat`, `ls_luxury` |
| `atl_loadmaster_habitat` | Atlas Concern | Loadmaster | 6 | Habitat | `ls_habitat` |

Ship templates: workhorses carry spartan habitat or transport packs that fit the hull; sporty and luxury hulls carry comfort or luxury. Pegasus P101 lore remains A1 spartan (four hot bunks); P103 lore remains A3 luxury (two-person cabin).

The POC `life_support_mk1` and `life_support_a3` placeholders are retired.

---

## Ship weapons (design catalog)

Types include mass driver, plasma, scatter, rockets, laser/turbo laser turrets, plasma burst, MDC turret, flak — with weight, damage rating, type, ROF, range, ammo.

**Original POC:** Mass Driver Cannon with damage signature `P,90-100` (projectile 90–100).

**Pegasus P101 lore:** mass driver for defence.  
**Flare-ON SS lore:** rotating laser turret.  
**Godot prototype:** light laser (hitscan beam) and light mass driver (kinetic projectile) fire along ship facing in orbital flight. Debris is destructible; stations and wrecks block shots.

### Weapon systems and ammo modules (design)

Hardpoints classified Type Q / W / E with max weapons and ammo module slots. Ammo modules: MDC, Plasma, Energy Cell, Rockets, Flak Shells.

---

## Personal weapons

| Name | Type |
|------|------|
| Stinger Automatic / St Luger .38 | Ranged (.22 calibre family) |
| Blade, Blunt Instrument | Melee |

**Galactic Outcomes** manufactures small arms in lore. Merchants in original world: Jasons Hardware, BCD Suppliers, Bobs Guns, Self Defence Emporium — closed in prototype.

### .22 pistol culture

Despite futuristic weapons, weight-conscious pilots favour **22-millimeter solid projectile pistols**:

- Best weight efficiency among projectiles
- Penetrates light body armour; most pilots avoid heavy armour bulk
- Ship internals typically proof against .22; larger kinetic or energy weapons risk hull damage and EM emissions

See [overview.md](overview.md).

---

## Damage model (design)

### Damage packet

Attacks resolve to typed amounts:

| Type code | Channel |
|-----------|---------|
| P | Projectile / kinetic |
| E | Energy |
| X | Explosive |
| C | Collision |

Example: `P,90-100` → 90–100 projectile damage (dice roll).

### Application order (ship)

1. **Armour** — reduces packet (stub in POC)
2. **Chassis** — subtracts converted damage from hits:
   - projectile ÷10, energy ÷5, explosive ÷5, collision ÷2

Extended **JMD** combat taxonomy (shield modes, guidance types) existed in design spreadsheet — not in prototype loop.

---

## Software (SnedeCorp)

Ship computer and onboard software monopoly in lore. Flare-ON SK markets "latest onboard software systems." No CPU slot gameplay in prototype.

---

## Prototype workshop behaviour

At **Habitat Workshop** (`kind: "workshop"`):

- Lists ships with `location` matching current habitat
- Buy/sell/install/remove modules from unified catalogue
- Refuel ships; inspect configuration and engineering budgets
- Chassis is fixed per owned ship

Planned: shield combat, hyperdrive slots — see README placeholders and [architecture.md](../design/architecture.md). Weapons firing (light laser, mass driver) is implemented in orbital flight.

---

## Catch-up checklist

When extending JSON after editing this bible:

1. Add module entries to `modules.json` with consistent ids and category
2. Propulsion modules require `maker`, `brand`, and `engine_type` (`chemical` | `hydro_thermal` | `electric_plasma` | `direct_fusion` | `antimatter` | `gravitic`). Power modules require `maker`, `brand`, and `plant_type` (`fission` | `fusion` | `radioisotope`); computer modules require `maker`, `brand`, and `core_type` (`silicon` | `photon` | `quantum`); life support modules require `maker`, `brand`, `life_support_capacity`, and `compute_demand`. Optional flags: `ls_habitat` (live-aboard), `ls_comfort`, `ls_luxury`. Volume includes cabin space.
3. Reference in `ships.json` templates and `player.json` instances
4. Extend `ShipAssembler` / `ShipOperations` if new stat fields matter for flight or operating budgets
5. Add corporate `maker` strings aligned with [corporations.md](corporations.md)
