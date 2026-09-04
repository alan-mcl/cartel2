# Data model

JSON catalog schemas and runtime types for the Godot prototype. For setting intent beyond what is catalogued today, see [setting docs](../setting/README.md).

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
| `sectors.json` | array | Sector identity, bounds, spawn, Unspace mappings |
| `unspaces.json` | array | N-space transit layouts (depth, spawn, world link) |
| `worlds.json` | object keyed by sector/unspace id | Orbital and 4-space entity layouts |
| `interactables.json` | array | Interaction definitions |
| `commodities.json` | array | Trade goods (mass, base_price) |
| `markets.json` | array | Building-linked commodity listings |

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

Category-specific fields include `thrust`, `max_speed`, `boost_multiplier`, `fuel_consumption`, `power_generation`, `power_demand`, `compute_capacity`, `compute_demand`, `life_support_capacity`, `cargo_capacity`, `fuel_capacity`, `hits` (armour), weapon stats, `ammunition_capacity` (object keyed by ammo type), etc.

**Categories in prototype:** `propulsion`, `power`, `computer`, `life_support`, `sensor`, `weapon`, `armour`, `cargo`, `fuel`, `ammunition`.

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

**Other** slots (`other_{n}`) hold volume-only modules (cargo, fuel, armour, magazines). Chassis `utility` counts are merged into `system` in the prototype catalog.

### `player.json`

```json
{
  "starting_sector": "proxima",
  "credits": 3000,
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
| `AssembledShip` | `assembled_ship.gd` | Resolved modules, capacities, envelope, derived stats |
| `ShipOperatingState` | `ship_operating_state.gd` | Transient power/fuel/compute state |
| `ShipAssembler` | `ship_assembler.gd` | Assemble, validate install, derive stats |
| `ShipOperations` | `ship_operations.gd` | In-flight operating tick |
| `ShipAssembly` | `ship_assembly.gd` | Fitting gameplay (buy/sell/install/remove/refuel) |

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

Fuel lives on the owned ship. Heat/signature simulation is deferred beyond this prototype.

## `player.json` and session

`PrototypeSession` (`scripts/gameplay/prototype_session.gd`):

| Field | Description |
|-------|-------------|
| `owned_ships` | `OwnedShip[]` — each carries its own `cargo` |
| `spare_parts` | `{ module_id: qty }` uninstalled modules in player inventory |
| `hull` / `max_hull` | Hull stress during 4-space (from chassis + armour hits) |

Cargo is **per ship**, not session-wide. Exchange buy/sell targets the selected docked ship (defaults to `current_ship_id`).

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
  "saved_at": "2026-09-01T12:00:00Z",
  "player": { "name": "Jane Doe", "callsign": "Vixen" },
  "session": { /* PrototypeSession.to_dict() — includes spare_parts */ },
  "ships": [ /* OwnedShip.to_dict() — modules, cargo, fuel, ammunition */ ],
  "flight": { "x": 0, "y": 0, "vx": 0, "vy": 0, "facing": -1.57 }
}
```

Version 1 saves are accepted; legacy `session.cargo` migrates onto `current_ship_id`.

**Not saved:** catalog data, derived `AssembledShip` / `ShipStats` (recomputed on load).

## Sectors, worlds, interactables, habitats

(Sector/world/interactable/habitat schemas unchanged — see previous sections in git history or setting docs.)

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
| Weapons | Catalogued; not fired in flight | Full combat loop |
| Operating sim | Power, fuel, compute in flight | Combat power contention, heat/signature, ammo consumption |

Canonical lore: [setting/ships.md](../setting/ships.md), [setting/equipment.md](../setting/equipment.md).
