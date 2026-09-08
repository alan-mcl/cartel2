# Equipment and components

**Status:** Full component taxonomy is **setting intent** from original design spreadsheet and notes. The Godot prototype JSON includes seven chassis, fourteen ship templates, engines through Mark 2 antimatter and gravitic, sensors, lasers, mass drivers, plasma/scatter/missile weapons, cargo/fuel modules, armour, and an alpha hyperdrive catalog entry (no translation gameplay). **Light laser and mass driver fire in orbital flight**; shields remain design-only.

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

Each chassis references a hull **sprite** path and **hull_color** for rendering.

---

## Modules (`modules.json`)

All equipment is defined in a single catalogue, filtered by `category`.

### Propulsion (`category: propulsion`, mount: `main_engine`)

Families in design: **Mark 1–6 Fusion**, **Mark 1–6 Antimatter**, **Mark 1–2 Gravitic**.

| Stat | JSON field | Prototype use |
|------|------------|---------------|
| Weight | `mass` | Ship mass |
| Thrust | `thrust` | Forward acceleration |
| Max speed | `max_speed` | Speed cap km/s |
| Fuel use | `fuel_consumption` | Consumed in flight |
| Boost | `boost_multiplier` | Boost speed factor |
| Power | `power_demand` | Operating budget |

### In prototype JSON

| id | Maker | Role |
|----|-------|------|
| `mark_3_fusion` | Bayes Inc | Flare-ON SS default |
| `mark_1_fusion` | Bayes Inc | Pegasus P101 default |
| `mark_2_antimatter` | Bayes Inc | Gunships, P103a, K3 |
| `gravitic_mk1` | Holt-Winters Corp | Flare-ON SK |

`ShipAssembler` derives `ShipStats` from loaded mass; `ShipOperations` ticks fuel, power, and compute in flight.

### Computer (`category: computer`, mount: `system`)

| id | Capabilities | Notes |
|----|--------------|-------|
| `nav_combat_core_mk1` | `basic_hud` | Speed/heading, fuel/power, GST clock in flight |

### Sensor (`category: sensor`, mount: `system`)

| id | Capabilities | Notes |
|----|--------------|-------|
| `sensor_basic` | `local_sensor`, `local_system_waypoints`, `sensor_read_beacons` | Local radar panel; edge arrows; transponder label overlay |
| `sensor_advanced` | same as basic | Extended-range sensors |

### Transponder (`category: transponder`, mount: `system`)

| id | Notes |
|----|-------|
| `vessel_registration_beacon` | Commercial Article 19 identification transmitter. Required in-system. Broadcasts registration + pilot callsign when powered (~0.3 MW). |

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

## Life support (design only)

Tiers **A1–A5**: capacity in man-hours, luxury level (none → bar).

- Pegasus P101 lore: A1 (spartan).
- Pegasus P103 lore: A3 (luxury).

Not simulated in prototype.

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
2. Reference in `ships.json` templates and `player.json` instances
3. Extend `ShipAssembler` / `ShipOperations` if new stat fields matter for flight or operating budgets
4. Add corporate `maker` strings aligned with [corporations.md](corporations.md)
