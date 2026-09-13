# Data model

JSON catalog schemas and runtime types for this game. For setting intent beyond what is catalogued today, see [setting docs](../setting/README.md).

Machine-readable schema files live under `data/catalog/schema/`; generated field tables are in [catalog_schema.md](catalog_schema.md). Regenerate typed records and validators with `python3 scripts/tools/generate_catalog_records.py`.

Full assembly design: [ship_assembly.txt](ship_assembly.txt).

## Catalog files

All catalog arrays are indexed by string `id` at load time. Duplicate ids log errors.

| File | Format | Purpose |
|------|--------|---------|
| `chassis.json` | array | Hull frames with mount envelopes |
| `modules/*.json` | array per category | All installable equipment split by `category` under `data/catalog/modules/` |
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
| `traffic.json` | object | In-system NPC traffic tuning (LOD, roles, cruise fraction) |

Loader: `scripts/gameplay/catalog.gd` — `Catalog.load_default()`. Modules merge from `data/catalog/modules/*.json` into `ModuleDef` records; `AssembledShip.installed_modules[].data` is `ModuleDef`. `commodities.json` and `economies.json` materialise as `CommodityDef` / `EconomyDef`; `economies.json` `produce`/`consume` object keys are schema-validated against commodity ids. Typed getters (`get_module_def`, `list_module_defs`, …) are preferred in assembly/combat/sensors; `get_module()` still returns `Dictionary` via `to_dict()` for yard UI. Chassis/ships/sectors dictionary getters remain until a later pass.

## ID conventions

- Lowercase snake_case: `proxima_habitat`, `hw_sundancer_compact`, `flare_on_ss_1`.
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

### `modules/*.json`

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

Category-specific fields include `thrust`, `max_speed`, `boost_multiplier`, `fuel_consumption`, `power_generation`, `power_demand`, `engine_type` (propulsion: `chemical` | `hydro_thermal` | `electric_plasma` | `direct_fusion` | `antimatter` | `gravitic`), `compute_capacity`, `compute_demand`, `core_type` (computer: `silicon` | `photon` | `quantum`), `plant_type` (power), `life_support_capacity`, `cargo_capacity`, `fuel_capacity`, `hits` (armour), weapon stats, `ammunition_capacity` (object keyed by ammo type), etc.

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
| `name` | string | Optional given ship name (distinct from pilot callsign) |
| `registration` | string | Vessel registration number (`VR-{PREFIX}-{NNNN}`) |
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
| `basic_hud` | any computer module (temporary gate) | Speed/heading, fuel/power, GST clock |
| `local_sensor` | `hg_hermes_n6` (nav packages) | North-up local-space radar panel |
| `local_system_waypoints` | `hg_hermes_n6` | Edge arrows toward habitat, jump gate, or exit portal |
| `sensor_read_beacons` | `hg_hermes_n6` | HUD transponder labels for NPC ships and named landmarks |
| `4_space_topology` | `hg_hermes_n6` | Unspace exit portal radar dot, edge arrow, and label (4-space only) |

Life support modules include cabin volume in `volume` (seats or bunks, not a recycler rack). Optional flags: `ls_habitat` (live-aboard bunks; **absence means transport seating**), plus `ls_comfort` / `ls_luxury` for future hospitality gameplay. Do not add `ls_transport`. A5 bar is reserved for later. Crew capacity is 1–6.

Capability gating is install-based; compute overload degradation is deferred.

### Transponder (Article 19)

In-system ships require an installed `vessel_registration_beacon` (`category: transponder`). When powered in flight, the beacon broadcasts hull registration and pilot callsign; optional ship name and (NPC-only) corporate affiliation may be included. Reader capability `sensor_read_beacons` replaces always-on world labels with HUD overlay text.

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
| `Simulation` | `simulation.gd` | Central tick owner: GST advance plus subsystem registry |
| `SimClock` | `sim_clock.gd` | Real-time and unspace GST advance (no subsystem dispatch) |
| `SimSubsystem` | `sim_subsystem.gd` | Base contract: `on_tick`, `on_hour`, `on_day`, `on_event`, save hooks |
| `EconomySubsystem` | `economy_subsystem.gd` | Reposts market quotes on day rollover |
| `GameClock` | `game_clock.gd` | Facade over `Simulation` for tests and legacy callers |

`Simulation.step` runs from `main.gd` when the game is active and GST is not frozen (menus, pause overlay, save/load overlay, jump picker). Habitat UI keeps GST running at 1:1 while docked.

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

- Density scales with `population_billions` on each sector (see `planets.md` lore). Proxima ≈ 100 ships at population max (`near_count_max + far_count_max`); full simulation capped by `sim_slot_max`.
- Initial spawn places trip roles (`transit`, `shuttle`, `dock_cycle`) 15–85% along origin→destination with lateral offset; `loiter` / `runabout` scatter near the jump gate and orbitals (not habitat). Cycle replacements still spawn at origin waypoints.
- Each actor uses a real `OwnedShip` assembled from manufacturer templates (`pegasus_p101`, `flare_on_ss`) and ticks `ShipOperations` + `ShipWeapons` (fuel, power, ammo).
- Roles: `transit`, `shuttle`, `loiter`, `runabout`, `dock_cycle` — tuned in `traffic.json`. Trip roles share one lifecycle: origin → destination (habitat, gate, or unnamed orbital) → despawn → fresh origin.
- Completing a route (habitat, gate, or orbital), running dry, or leaving bounds **retires** the sprite; the director spawns a fresh replacement so fleet density stays constant.
- Provoked combat only: NPCs engage or flee; player hull remains invulnerable this slice.
- Sensor HUD: smaller unlabelled NPC blips across the sector and unlabelled orbital dots on the local radar.

### `traffic.json`

| Field | Type | Description |
|-------|------|-------------|
| `near_lod_radius` | number | Legacy distance hint; presentation and full sim follow `sim_slot_max` |
| `sim_slot_max` | number | Max ships with full systems tick + `NpcShip` physics (default ~20) |
| `sim_slot_hysteresis` | number | Distance grace (m) to keep a slot when a ship was previously slotted |
| `sensor_contact_radius` | number | Minimap blip range for NPC ships (typically ~gate radius; independent of dust ring) |
| `cruise_speed_fraction` | number | Peaceful cruise cap as fraction of assembled hull `max_speed` (e.g. 0.33) |
| `cruise_speed_jitter` | number | Per-ship multiplier spread around cruise fraction (e.g. 0.2 → ~26–40% of max) |
| `waypoint_weight_habitat` / `jump_gate` / `orbital_each` | number | Weighted pick for trip origin/destination and loiter/runabout anchor bias |
| `route_lateral_offset_min` / `route_lateral_offset_max` | number | Perpendicular scatter for mid-route arrival spawn |
| `local_scatter_radius_min` / `local_scatter_radius_max` | number | Ring offset for loiter/runabout arrival spawn near gate/orbitals |
| `near_count_min` / `max` | number | Near-LOD fleet size range (log-scaled by population) |
| `far_count_min` / `max` | number | Far-LOD fleet size range |
| `role_weights_default` | object | Role spawn weights |
| `sector_overrides` | object | Per-sector role weight overrides |
| `role_ship_templates` | object | Template id(s) per role |
| `callsign_prefixes` | object | Hull template id → registration prefix (`VR-{prefix}-{NNNN}`) |
| `independent_weight` | number | Fraction of NPC traffic assigned `Independent Operator` (default 0.30) |
| `affiliations` | array | Operator records: `{ id, kind, name, callsign_prefix? }`. `kind` is `corporate` or `independent`. Corporate `callsign_prefix` is the stock ticker from [corporations.md](../setting/corporations.md) (e.g. `HW`, `SNE`). |
| `independent_callsigns` | array | Full personal pilot callsigns for independents and New Game defaults |
| `independent_callsign_prefixes` / `independent_callsign_roots` | array | Optional combinatoric parts (`{Prefix} {Root}`) when both are non-empty |
| `vanity_ship_names` | array | Hull given names; always assigned to independent operators, never to corporate |

**NPC identity:** corporate ships broadcast `{TICKER}-{NNN}` callsigns (e.g. `HW-447`) and affiliation only — no hull name. Independent ships always receive a name from `vanity_ship_names` and a personal callsign from the independent lists. Player callsign at New Game is pre-filled from `independent_callsigns` but remains editable.

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
