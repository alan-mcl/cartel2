# Data model

JSON catalog schemas and runtime types for the Godot prototype. For setting intent beyond what is catalogued today, see [setting docs](../setting/README.md).

## Catalog files

All catalog arrays are indexed by string `id` at load time. Duplicate ids log errors.

| File | Format | Purpose |
|------|--------|---------|
| `chassis.json` | array | Hull frames |
| `engines.json` | array | Propulsion |
| `armour.json` | array | Armour plates |
| `ships.json` | array | Ship templates (default loadouts) |
| `player.json` | object | Starting sector, credits, owned ship instances |
| `habitats.json` | array | Orbital habitats and building lists |
| `buildings.json` | array | Visit locations within habitats |
| `sectors.json` | array | Sector identity, bounds, spawn, Unspace mappings |
| `unspaces.json` | array | N-space transit layouts (depth, spawn, world link) |
| `worlds.json` | object keyed by sector/unspace id | Orbital and 4-space entity layouts |
| `interactables.json` | array | Interaction definitions |

Loader: `scripts/gameplay/catalog.gd` — `Catalog.load_default()`.

## ID conventions

- Lowercase snake_case: `proxima_habitat`, `mark_3_fusion`, `flare_on_ss_1`.
- Habitat ids match dock `location_id` on owned ships when parked.
- Sector ids in `worlds.json` keys must match `sectors.json` ids.
- World entity ids are unique within a sector layout; interactable ids reference `interactables.json`.

## `player.json`

```json
{
  "starting_sector": "proxima",
  "credits": 3000,
  "ships": [ /* owned instances */ ]
}
```

### Owned ship instance

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique instance id |
| `name` | string | Display / call sign |
| `template_id` | string | Reference to `ships.json` (metadata, default weapons) |
| `chassis_id` | string | Current chassis |
| `engine_id` | string | Current engine |
| `armour_id` | string \| null | Current armour (empty/null = none) |
| `location` | string | `"aboard"` or habitat id (e.g. `proxima_habitat`) |

- **aboard** — ship the player flies in orbit.
- **habitat id** — parked at that habitat; persists across sector jumps.
- Docking sets current ship `location` to the docked habitat id.
- Undocking sets chosen ship to `aboard` and updates `current_ship_id`.

## Ship modules

### `chassis.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | |
| `name` | string | |
| `maker` | string | Corporation name |
| `mass` | number | Tonnes |
| `hits` | number | Structural integrity (not used in flight prototype) |
| `max_load` | number | Cargo capacity tonnes |
| `maneuver` | string | `low` \| `medium` \| `high` → rotation and damp |
| `hull_color` | string | HTML colour for sprite modulate |
| `sprite` | string | `res://` path to hull art |

### `engines.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | |
| `name` | string | |
| `maker` | string | |
| `mass` | number | Tonnes |
| `thrust` | number | Design thrust (input to assembler) |
| `max_speed` | number | km/s cap |
| `boost_multiplier` | number | Boost speed factor |

### `armour.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | |
| `name` | string | |
| `maker` | string | |
| `mass` | number | Tonnes |
| `hits` | number | Armour pool (not used in flight prototype) |

### `ships.json`

Template record; owned instances override module ids.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Template id |
| `name` | string | |
| `maker` | string | |
| `chassis` | string | Default chassis id |
| `engine` | string | Default engine id |
| `armour` | string \| null | Default armour |
| `weapons` | array | Weapon ids (empty in prototype) |

### Derived flight stats

`ShipAssembler._derive_stats` combines chassis + engine + armour:

- Total mass = sum of module masses
- `forward_thrust` = engine thrust / mass × scale
- `reverse_thrust` = forward × ratio
- `max_speed`, `boost_max_speed` from engine (boost capped)
- `rotation_speed`, `linear_damp` from chassis `maneuver` tier

Workshop swaps update owned ship module ids immediately; `main.gd` re-assembles and reconfigures the player ship when the aboard ship changes.

## Sectors and worlds

### `sectors.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Sector key (e.g. `proxima`) |
| `name` | string | Full name ("Proxima Sector") |
| `orbit_name` | string | HUD location while in orbit |
| `play_bounds` | number | Dust ring radius (world units) |
| `spawn` | `{ x, y }` | Player position after sector load / jump |
| `objective` | string | HUD objective text |
| `mappings` | array | Known Unspace routes from this sector |

#### Mapping entry

| Field | Type | Description |
|-------|------|-------------|
| `target` | string | Destination sector id |
| `solution` | number | Known Unspace integer (flavour; typing not implemented) |
| `n` | number | N-space depth for this route (4 = shallowest playable) |
| `label` | string | Button text in jump overlay |

Example: Proxima → Bela uses solution **42** at **n=4**; Bela → Proxima uses **−34458** at **n=4**.

### `unspaces.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unspace layout id (e.g. `n4_default`) |
| `n` | number | N-space depth (4 = lowest above 3-space realspace) |
| `name` | string | Display name |
| `orbit_name` | string | HUD location while in transit |
| `play_bounds` | number | Boundary radius |
| `spawn` | `{ x, y }` | Entry position in 4-space |
| `objective` | string | Default objective text |
| `world_id` | string | Key in `worlds.json` for entity layout |

### `worlds.json`

Top-level object: `{ "sector_id": { "entities": [ ... ] } }`.

#### World entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique within sector |
| `kind` | string | yes | See kinds below |
| `position` | `{ x, y }` | yes | World coordinates |
| `rotation` | number | no | Radians |
| `scale` | `{ x, y }` | no | Default 1,1 |
| `label` | string | no | Label node text |
| `interactable` | string | no | Interactable catalog id |
| `sprite` | string | no | Override texture path |
| `modulate` | string | no | HTML colour (e.g. water-world tint) |

**Kinds:** `habitat`, `jump_gate`, `beacon`, `wreck`, `debris`, `planet_limb`, `hazard`.

Hazard entities support `radius`, optional `shear_strength`, `hull_stress`.

Dust ring is **not** in JSON; generated from `play_bounds`.

## Interactables

### `interactables.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | |
| `title` | string | Display name |
| `inspect_text` | string | Flavour / log on interact |
| `kind` | string | `inspect` \| `salvage` \| `dock` \| `translate` \| `arrive` |
| `salvage_reward` | number | Credits (salvage only) |
| `dock_location_id` | string | Habitat id (dock only) |

Translate interactables open the route overlay; `arrive` interactables complete 4-space transit at exit portals.

Runtime: `InteractableDef.from_dict()` — `RefCounted`, not a Godot Resource.

## Habitats and buildings

### `habitats.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Matches dock `dock_location_id` |
| `name` | string | |
| `short_desc` | string | |
| `default_building` | string | Opened on dock |
| `buildings` | string[] | Visit list |

### `buildings.json`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | |
| `name` | string | |
| `kind` | string | `terminal`, `landmark`, `merchant`, `workshop`, … |
| `short_desc` | string | |

Workshop (`kind: "workshop"`) enables module swap UI for ships with `location` equal to current `habitat_id`.

## Runtime session state

`PrototypeSession` (`scripts/gameplay/prototype_session.gd`):

| Field | Description |
|-------|-------------|
| `sector_id` | Current 3-space sector (when not in unspace) |
| `in_unspace` | Flying through N-space transit |
| `unspace_n` | Current N-space depth |
| `unspace_world_id` | Active unspace layout id |
| `pending_destination_id` | Target sector after exit portal |
| `hull` / `max_hull` | Hull stress during 4-space (from chassis hits) |
| `location_name` | Orbit name or `"Habitat / Building"` when docked |
| `credits` | Player credits |
| `objective` | HUD string |
| `last_log` | Recent action message |
| `salvaged_ids` | Interactable ids already salvaged |
| `inspected_ids` | Interactable ids inspected at least once |
| `docked` | In habitat menu |
| `habitat_id`, `building_id` | Current dock context |
| `owned_ships` | `OwnedShip[]` |
| `current_ship_id` | Aboard ship id |

Key methods: `enter_sector`, `enter_unspace`, `arrive_from_unspace`, `apply_hull_stress`, `dock`, `visit`, `undock`, `salvage`, `inspect`, `set_module`, `get_spawn_position`.

## How to extend

### Add an orbit object

1. Add interactable to `interactables.json` if the object is interactive.
2. Add entity to `worlds.json` under the sector's `entities` array.
3. Ensure `kind` is mapped in `WorldLoader.SCENES` (or handled for `planet_limb`).
4. Reimport / run.

### Add a building

1. Entry in `buildings.json`.
2. Add building id to habitat's `buildings` array in `habitats.json`.

### Add a sector

1. Entry in `sectors.json` with spawn, bounds, mappings.
2. Layout in `worlds.json` under new sector id.
3. Habitats / interactables as needed.
4. Optionally set `player.json` `starting_sector` for testing.

## Implemented subset vs setting

| Area | In JSON today | Setting target |
|------|---------------|----------------|
| Sectors | Proxima, Bela | Six starter systems |
| Chassis | Flare-ON, Pegasus | Seven+ families |
| Engines | Mark 1, Mark 3 Fusion | Fusion, antimatter, gravitic tiers |
| Armour | 5mm Chitanium | Titanium/endosteel range |
| Weapons | None | Mass driver, lasers, plasma, … |
| Shields, LSS, hyperdrive | None | Full design tables |
| On-foot cities | None | Roadmaps per planet |

Canonical lore and full catalogs: [setting/planets.md](../setting/planets.md), [setting/ships.md](../setting/ships.md), [setting/equipment.md](../setting/equipment.md).
