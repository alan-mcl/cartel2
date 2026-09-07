# Data model

JSON catalog schemas and runtime types for this game. For setting intent beyond what is catalogued today, see [setting docs](../setting/README.md).

Full assembly design: [ship_assembly.txt](ship_assembly.txt).

## Catalog files

All catalog arrays are indexed by string `id` at load time. Duplicate ids log errors.

| File | Format | Purpose |
|------|--------|---------|
| `chassis.json` | array | Hull frames with mount envelopes |
| `modules.json` | array | All installable equipment (propulsion, power, weapons, cargo, …) |
| `ammunition.json` | array | Ammunition type definitions (mass, cost) |
| `ships.json` | array | Manufacturer templates (recommended module loadouts) |
| `player.json` | object | New-game template: starting sector, credits, owned ship instances |
| `habitats.json` | array | Orbital habitats and building lists |
| `buildings.json` | array | Visit locations within habitats |
| `sectors.json` | array | Sector identity, bounds, spawn (mappings synthesized from `routes.json`) |
| `routes.json` | array | Public Unspace trade network (undirected edges, friction, solutions) |
| `economies.json` | array | Per-sector production/consumption profiles and network tier |
| `unspaces.json` | array | N-space transit layouts (depth, spawn, world link) |
| `worlds.json` | object keyed by sector/unspace id | Orbital and 4-space entity layouts |
| `interactables.json` | array | Interaction definitions |
| `commodities.json` | array | Trade goods (mass, base_price) |
| `markets.json` | array | Legacy static listings (unused; quotes are runtime) |
| `traffic.json` | object | In-system NPC traffic tuning (LOD, roles, cruise fraction) |

Loader: `scripts/gameplay/catalog.gd` — `Catalog.load_default()`.

## ID conventions

- Lowercase snake_case: `proxima_habitat`, `mark_3_fusion`, `flare_on_ss_1`.
- Habitat ids match dock `location_id` on owned ships when parked.
- Sector ids in `worlds.json` keys must match `sectors.json` ids.
- World entity ids are unique within a sector layout; interactable ids reference `interactables.json`.

## Ship construction model

```
Chassis (envelope + mounts)
  └── installed modules (slot → module_id)
        └── aggregated capacities + derived flight stats
              └── operating state (power, fuel, compute — in flight)
```

**Static fitting** validates mount compatibility, mass limit, and volume. **Operating overload** (e.g. weapons drawing more power than the plant generates while firing) is allowed at install time; `ShipOperations.tick` resolves power/fuel/compute during flight.

### `chassis.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | |
| `name` | string | |
| `maker` | string | Corporation name |
| `mass` | number | Hull structural mass (tonnes) |
| `hits` | number | Base structural integrity |
| `mass_limit` | number | Maximum configured ship mass (tonnes) |
| `volume` | number | Internal volume envelope (m³) |
| `maneuver` | string | `low` \| `medium` \| `high` → rotation and damp |
| `mounts` | object | Mount category → count (e.g. `main_engine: 1`, `system: 5`) |
| `hull_color` | string | HTML colour for sprite modulate |
| `sprite` | string | `res://` path to hull art |

### `modules.json`

Common fields (omit zero-valued properties):

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | |
| `name` | string | |
| `maker` | string | |
| `category` | string | See categories below |
| `mount` | string | Single required mount category |
| `mounts` | string[] | Optional; when present, module may install in any listed mount (tried in order for auto-assignment) |
| `mass` | number | Tonnes |
| `volume` | number | m³ |
| `cost` | number | Yard purchase price |
| `description` | string | |
| `capabilities` | string[] | Optional feature tags aggregated onto `AssembledShip` (e.g. `basic_hud`, `local_sensor`) |

Category-specific fields include `thrust`, `max_speed`, `boost_multiplier`, `fuel_consumption`, `power_generation`, `power_demand`, `compute_capacity`, `compute_demand`, `life_support_capacity`, `cargo_capacity`, `fuel_capacity`, `hits` (armour), weapon stats, `ammunition_capacity` (object keyed by ammo type), etc.

**Categories in current JSON:** `propulsion`, `power`, `computer`, `life_support`, `sensor`, `hyperdrive`, `weapon`, `armour`, `cargo`, `fuel`, `ammunition`.

Use `"mount": "system"` (or another single mount) for modules with one home. Use `"mounts": ["other", "light_weapon", …]` when a part can fit multiple slot types. Omit both for Other-only modules (`ShipAssembler.module_mounts()` defaults to `["other"]`).

### `ships.json` (template)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Template id |
| `name` | string | |
| `maker` | string | |
| `chassis` | string | Chassis id |
| `modules` | string[] | Recommended module ids (assigned to slots at new game) |

### Slot naming

Mounted modules use `{mount_category}_{n}` (e.g. `main_engine_1`, `system_3`, `light_weapon_1`).

**Other** slots (`other_{n}`) hold volume-only modules (cargo, fuel, armour, magazines). Chassis `utility` counts are merged into `system` in the current catalog.

### `player.json`

```json
{
  "starting_sector": "proxima",
  "credits": 3000,
  "gst": {
    "year": 2646,
    "month": 1,
    "day": 1,
    "hour": 8,
    "minute": 0,
    "second": 0
  },
  "ships": [ /* owned instances */ ]
}
```

New Game reads this template once; runtime progress is stored in save slots under `user://saves/`.

### Owned ship instance

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique instance id |
| `name` | string | Display / call sign |
| `template_id` | string | Reference to `ships.json` |
| `chassis_id` | string | Fixed chassis |
| `modules` | array | `{ slot, module_id }` installed configuration |
| `fuel_current` | number | Stored propulsion fuel |
| `ammunition` | object | `{ ammo_type_id: qty }` |
| `cargo` | object | `{ commodity_id: qty }` per-ship hold |
| `location` | string | `"aboard"` or habitat id |

Save v1 ships with `engine_id` / `armour_id` are migrated on load to `main_engine_1` / `other_1`. Legacy `internal_*` and `utility_*` slot names migrate to `other_*` / next free `system_*`.

- **aboard** — ship the player flies in orbit.
- **habitat id** — parked at that habitat; persists across sector jumps.

## Runtime ship types

| Type | File | Role |
|------|------|------|
| `OwnedShip` | `owned_ship.gd` | Persistent configuration + inventories |
| `AssembledShip` | `assembled_ship.gd` | Resolved modules, capacities, capabilities, envelope, derived stats |
| `ShipOperatingState` | `ship_operating_state.gd` | Transient power/fuel/compute state |
| `ShipAssembler` | `ship_assembler.gd` | Assemble, validate install, derive stats |
| `ShipOperations` | `ship_operations.gd` | In-flight operating tick |
| `ShipAssembly` | `ship_assembly.gd` | Fitting gameplay (buy/sell/install/remove/refuel) |
| `TrafficDirector` | `traffic_director.gd` | Spawns/ticks ephemeral NPC fleet in 3-space |
| `TrafficActor` | `traffic_actor.gd` | Single NPC ship AI + operating state |

### Capabilities (flight UI)

`ShipAssembler` unions each installed module's `capabilities[]` onto `AssembledShip.capabilities`. Presentation code calls `AssembledShip.has_capability(id)` to gate HUD features:

| Capability | Typical grantor | Unlocks |
|------------|-----------------|---------|
| `basic_hud` | `nav_combat_core_mk1` (computer) | Speed/heading, fuel/power, GST clock |
| `local_sensor` | `sensor_basic` | North-up local-space radar panel |
| `local_system_waypoints` | `sensor_basic` | Edge arrows toward habitat, jump gate, or exit portal |

Capability gating is install-based; compute overload degradation is deferred.

### Derived flight stats

`ShipAssembler.derive_stats` uses **loaded mass** = dry module mass + fuel mass + cargo mass + ammunition mass:

- `forward_thrust` = engine thrust / loaded_mass × scale
- Maneuver rotation/damp from chassis tier
- Boost speed capped at 980 km/s

### Operating state (in flight)

`ShipOperations.tick` each physics frame:

- Allocates power by priority (life support + propulsion critical; sensors/computer high; weapons normal)
- Consumes fuel from `owned.fuel_current`
- Sets `thrust_factor` when fuel empty or power deficit

Fuel lives on the owned ship. Heat/signature simulation is deferred beyond the current build.

## `player.json` and session

`GameSession` (`scripts/gameplay/game_session.gd`):

| Field | Description |
|-------|-------------|
| `owned_ships` | `OwnedShip[]` — each carries its own `cargo` |
| `spare_parts` | `{ module_id: qty }` uninstalled modules in player inventory |
| `hull` / `max_hull` | Hull stress during 4-space (from chassis + armour hits) |
| `gst_seconds` | Elapsed GST since 1 January Q1, year 0 (float; persisted in saves) |

Cargo is **per ship**, not session-wide. Exchange buy/sell targets the selected docked ship (defaults to `current_ship_id`).

### Galactic Standard Time

| Type | File | Role |
|------|------|------|
| `GalacticCalendar` | `galactic_calendar.gd` | 364-day GSC math, timestamp formatting |
| `GameClock` | `game_clock.gd` | Real-time tick, unspace irregular pulses, mapping translation lumps |

`GameClock.tick` runs from `main.gd` when the game is active and GST is not frozen (menus, pause overlay, save/load overlay, jump picker). Habitat UI keeps GST running at 1:1 while docked.

**Sector mapping time fields** (on each object in `sectors.json` → `mappings[]`):

| Field | Type | Description |
|-------|------|-------------|
| `entry_seconds` | number | GST consumed when translating into unspace on this route |
| `exit_seconds` | number | GST consumed when emerging at the destination |
| `time_jitter` | number | ± fraction applied to each lump (e.g. `0.08` → ±8%) |

**Unspace GST overrides** (optional on `unspaces.json` entries under `gst`): `pulse_min`, `pulse_max`, `stretch_min`, `stretch_max`, `slip_chance`, `slip_min`, `slip_max` — control irregular time flow while flying in N-space. Deeper N uses larger depth multiplier in code.

### Ship assembly (`ShipAssembly`)

- `buy_part` / `sell_part` — yard stock ↔ credits ↔ `spare_parts`
- `install_module` / `remove_module` — any compatible slot; validates mass/volume/mount
- `refuel_ship` — fill fuel tank toward capacity for credits
- `preview_stats` / `get_engineering_block` — configuration + engineering readout for shipyard UI

Chassis is **fixed**; undock is allowed even with incomplete fits (no thrust without engine/fuel).

## Save files

Three slots at `user://saves/slot_1.json` … `slot_3.json`. `SaveStore.SAVE_VERSION` = **2**.

```json
{
  "version": 2,
  "game_version": "DEV",
  "saved_at": "2026-09-01T12:00:00Z",
  "player": { "name": "Jane Doe", "callsign": "Vixen" },
  "session": { /* GameSession.to_dict() — includes spare_parts */ },
  "ships": [ /* OwnedShip.to_dict() — modules, cargo, fuel, ammunition */ ],
  "flight": { "x": 0, "y": 0, "vx": 0, "vy": 0, "facing": -1.57 }
}
```

Version 1 saves are accepted; legacy `session.cargo` migrates onto `current_ship_id`.

**Not saved:** catalog data, derived `AssembledShip` / `ShipStats` (recomputed on load).

## In-system NPC traffic (3-space)

Ephemeral civilian ships in sector orbit only (not Unspace). Implemented by `TrafficDirector` + `TrafficActor` in `scripts/gameplay/`, presented by `NpcShip` in `scripts/presentation/`.

- Density scales with `population_billions` on each sector (see `planets.md` lore). Proxima ≈ 60 ships, La Bella Vista ≈ 35 after ~25% cap reduction.
- Initial spawn places route-following roles mid-corridor (15–85% along habitat/gate/orbital legs); cycle replacements still appear at endpoints.
- Each actor uses a real `OwnedShip` assembled from manufacturer templates (`pegasus_p101`, `flare_on_ss`) and ticks `ShipOperations` + `ShipWeapons` (fuel, power, ammo).
- Roles: `transit`, `shuttle`, `loiter`, `runabout`, `dock_cycle` — tuned in `traffic.json`.
- Completing a route (habitat, gate, or orbital), running dry, or leaving bounds **retires** the sprite; the director spawns a fresh replacement so fleet density stays constant.
- Provoked combat only: NPCs engage or flee; player hull remains invulnerable this slice.
- Sensor HUD: smaller unlabelled NPC blips across the sector and unlabelled orbital dots on the local radar.

### `traffic.json`

| Field | Type | Description |
|-------|------|-------------|
| `near_lod_radius` | number | Full physics/sim radius around player |
| `sensor_contact_radius` | number | Minimap blip range for NPC ships (typically matches sector `play_bounds`) |
| `cruise_speed_fraction` | number | Peaceful cruise cap as fraction of assembled hull `max_speed` (e.g. 0.5) |
| `cruise_speed_jitter` | number | Per-ship multiplier spread around cruise fraction (e.g. 0.2 → ~40–60% of max) |
| `route_lateral_offset_min` / `max` | number | Perpendicular scatter at initial mid-route spawn (not steering target) |
| `near_count_min` / `max` | number | Near-LOD fleet size range (log-scaled by population) |
| `far_count_min` / `max` | number | Far-LOD fleet size range |
| `role_weights_default` | object | Role spawn weights |
| `sector_overrides` | object | Per-sector role weight overrides |
| `role_ship_templates` | object | Template id(s) per role |

### `sectors.json` (addition)

| Field | Type | Description |
|-------|------|-------------|
| `population_billions` | number | Drives traffic density (log-scaled fleet size) |

## Sectors, worlds, interactables, habitats

Each sector in `sectors.json` has an empty `mappings[]` in JSON; at load time `Catalog` synthesizes bidirectional mappings from `routes.json`. Each mapping includes `target`, `solution`, `n`, `label`, `friction`, `entry_seconds`, `exit_seconds`, and `time_jitter`. GST lumps use `friction × 240` seconds.

`habitats.json` entries include `sector_id` for market quote lookup. Exchange buildings use `type: market`.

Daily commodity quotes are computed at runtime by `CommodityEconomy` from `economies.json`, `routes.json`, and `commodities.json`. Session stores `market_quotes` and `market_quotes_day` (recomputed on load from `gst_seconds`).

Other sector/world/interactable/habitat schemas unchanged — see setting docs.

## How to extend

### Add a module

1. Add entry to `modules.json` with `category`, optional `mount`, mass/volume, and category stats.
2. Reference in `ships.json` template if part of a default loadout.
3. Set `cost` for shipyard purchase.

### Add a ship template

1. Ensure chassis exists with appropriate `mounts`.
2. Add `ships.json` record with `modules[]` list.
3. Add owned instance to `player.json` with explicit slot assignments, or rely on auto-assignment from template.

## Implemented subset vs setting

| Area | In JSON today | Setting target |
|------|---------------|----------------|
| Ship model | Chassis + modules + budgets | Full Elite-style fitting + combat |
| Modules | Fusion engines, power, LS, sensors, lasers, mass drivers, cargo, fuel | Shields, ECM, hyperdrive, passenger classes |
| Weapons | Light laser and mass driver fire in flight; debris destructible; NPC traffic engage/flee | Full combat loop, shields, player hull damage |
| Operating sim | Power, fuel, compute in flight; weapon power while firing; NPC ships use same tick | Combat power contention, heat/signature, full ammo logistics |

Canonical lore: [setting/ships.md](../setting/ships.md), [setting/equipment.md](../setting/equipment.md).
