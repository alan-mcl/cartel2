# N-space and Unspace transit

**Status:** Playable 4-space transit with a single catalog presentation world (`n4_default`). Public routes already list **5-space** and **6-space** translations (timing, nav tiers, jump UI); in-flight transit still loads the 4-space field and meshes. Session state, HUD labels, and route seeding use the **real** translation N. See [translations.md](translations.md) for jump selection, accuracy, and stability; [gst.md](gst.md) for clock behaviour; [field_conditions.md](field_conditions.md) for ambient fields in transit.

Setting vocabulary (Unspace, layers, solutions) is in [overview.md](../../setting/overview.md). This document is the **implementation spec** for what the Godot build does today and what remains placeholder.

## Terminology

| Term | Meaning in code |
|------|-----------------|
| **3-space** | Normal sector orbit play (`WorldLoader.load_sector`). |
| **N-space / Unspace** | Higher-order translation layers used for inter-sector travel (`WorldPresence.in_unspace`). |
| **Translation N** | The layer encoded on the chosen route mapping (`mapping.n`). Stored as `WorldPresence.unspace_n` for the whole crossing. |
| **Presentation world** | Catalog unspace record loaded by `WorldLoader.load_unspace` (`WorldPresence.unspace_world_id`). Today always `n4_default` regardless of translation N. |
| **Solution** | Integer identifying a stored mapping; seeds field geometry and portal placement (`WorldPresence.unspace_solution`). |

## Layer catalogue (current)

| Translation N | Route data | Nav computer tier (typical) | Transit presentation |
|---------------|------------|----------------------------|----------------------|
| **4** | Every public edge; beacons offer 4-space only | Always loaded from current sector | `unspaces.json` → `n4_default` |
| **5** | Subset of edges with extra `translations[]` entries | Loaded when `nav_rating` ≥ 55 (subject to capacity) | Same as 4-space (`presentation_n` hard-coded to 4 in `GameSession.enter_unspace`) |
| **6** | Subset of edges (often alongside 4 and 5) | Loaded when `nav_rating` ≥ 75 | Same as 4-space |
| **7–9** | Not in public routes | Not offered | Not implemented (backlog: full layer stack) |

There is **one** row in [`unspaces.json`](../../../data/catalog/unspaces.json). `Catalog.get_unspace_for_n(n)` returns the catalog entry whose `n` field matches; only `n = 4` exists, so higher layers cannot get distinct worlds until new catalog rows and `enter_unspace` presentation selection are added.

[`worlds.json`](../../../data/catalog/worlds.json) keys each unspace id (`n4_default` has an empty `entities` list). Unspace layout lives in `unspaces.json` **`field`** blocks, not in world entity lists.

## Session state while in transit

Persisted on `WorldPresence` (facaded on `GameSession`):

| Field | Role |
|-------|------|
| `in_unspace` | True from successful `enter_unspace` until `arrive_from_unspace`. |
| `unspace_n` | Translation layer for this jump (4, 5, or 6 in public data). |
| `unspace_world_id` | Presentation catalog id (currently always `n4_default`). |
| `unspace_solution` | Solution integer from the confirmed mapping. |
| `pending_destination_id` | Sector id to enter on exit. |
| `translation_stability` | Rolled at jump confirm; shown on Fields HUD until emergence. |
| `location_name` | Set to `"N-space"` pattern (`"%d-space" % n`) for UI. |

Saves validate that `unspace_world_id` exists and `pending_destination_id` is non-empty while `in_unspace`.

## Entering Unspace

High-level pipeline (detail in [architecture.md](../architecture/architecture.md)):

1. Player confirms a translation at a jump gate, translation beacon, hyperdrive spool, or volatile outbound hop.
2. `TranslationNav.roll_stability` sets `translation_stability`.
3. GST **entry** lump from the translation’s `entry_seconds` (see [translations.md](translations.md)).
4. `GameSession.enter_unspace(catalog, destination_id, n, assembled_ship, solution)` resolves the mapping (catalog route, volatile record, or public fallback), checks destination and `n`, then sets session flags.
5. `WorldLoader.load_unspace` builds `NspaceField` from `unspace_world_id` (not from `unspace_n`).
6. Player placed at catalog spawn (`unspaces.json` `spawn`, defaulting near `-0.45 × play_bounds` on X).

**Mapping resolution order:** `catalog.get_translation(sector, solution)` → volatile resolver → `get_public_translation(sector, destination, n)`.

**Presentation vs translation N:** `enter_unspace` sets `presentation_n := 4` and loads `get_unspace_for_n(presentation_n)`. Translation N only affects labels, GST erraticity claims in design copy, stability roll inputs, and `_derive_route_seed(solution, n, salt)` for the field mesh.

**Volatile outbound:** Consumes the outbound hop when leaving a non-volatile source; destination may be a minimal volatile sector (separate loader path on arrival—not the `n4_default` field).

## Transit field (`NspaceField`)

Implemented in `scripts/presentation/nspace_field.gd`, configured from the catalog **`field`** object:

### Topology

- Poisson-scattered vertices inside a play disc (`play_bounds`, default **8000**).
- Delaunay triangulation with optional convex **quad merges** (`quad_merge_chance`).
- Independent random **heights** per vertex; 2D motion uses normal ship physics; heights feed **3D backdrop** only (no terrain collision or thrust from the mesh).
- Vertex count scales with viewport FOV margin (`fov_vertex_count`, `scatter_margin`, `vertex_count_min` / `max`).

### Route seeding

`route_seed = hash("%d:%d:%d" % [solution, n, seed_salt])` drives RNG for scatter, portal face choice, and face colours. Same solution and N → same field layout; different N on the same edge → different layout even on the shared presentation world.

### Exit portal

- One host face chosen at configure time: centroid in an annulus (`origin_min_fraction`–`origin_max_fraction` of `play_bounds`), away from entry spawn hint (`spawn_separation_fraction`), scored with `score_spawn_weight`.
- Interactable id `unspace_exit` (requires **`4_space_topology`** sensor capability for nav labelling).
- 3D disc in `NspaceBackdrop3D`; 2D `Area2D` for `[E]` interact.

### Ascidians

- Count **1–3** per crossing (`inhabitants` block); spawn uses visit RNG (not route seed), wander within `wander_radius_fraction × play_bounds`.
- Radar contacts as `ascidian_*`; behaviour in `scripts/presentation/ascidian.gd`.
- **Not** yet driven by translation stability or N-specific hazard tables.

### Presentation

- Isolated `SubViewport` (`own_world_3d`) composited behind the 2D ship.
- Orthographic camera tracks `Camera2D`; palette from catalog `field.palette`.
- No orbital dust ring in Unspace (unlike 3-space sectors).

### Play bounds

`WorldController` sets `Main.play_bounds` from the loaded unspace entry. Local radar scales to this radius. The topo mesh extends beyond the disc for FOV fill; this is **not** infinite navigation (backlog: infinite unspace nav and retuned spawn/portal randomisation).

## Exiting Unspace

1. `[E]` on exit portal interactable.
2. GST **exit** lump from the same translation’s `exit_seconds`.
3. `GameSession.arrive_from_unspace` clears unspace flags and stability, then `enter_sector(pending_destination_id)`.
4. Hull is **not** repaired on arrival (unlike some habitat repair flows).

## GST during transit

`SimClock` uses the **presentation** world’s `gst` block (`unspaces.json`), not translation N:

- Real time advances in **pulses** with random interval (`pulse_min`–`pulse_max`), stretch factor (`stretch_min`–`stretch_max`), and optional **slips** (`slip_chance`, `slip_min`–`slip_max`).
- Menu/jump overlay **freezes** GST; pause resets unspace pulse state via `reset_unspace_pulse`.

Design note in [gst.md](gst.md) says higher N should feel more erratic; **code does not** scale pulses by `unspace_n` yet.

## Field conditions and propulsion

When `in_unspace`, `FieldConditions` uses the fixed Unspace profile (low fluctuating G ~0.005–0.03, low radiant, fluctuating magnetic and particle indices)—see [field_conditions.md](field_conditions.md).

Gravitic and sail drives respond to those samples; other engines ignore local fields.

## Combat and hull

- Shots in Unspace do not record lawful-fire sanctions yet ([missions.md](missions.md)).
- `CombatPersistence.apply_hull_stress` can decrement hull only while `in_unspace` (cooldown **0.45** s); **`GameSession.apply_hull_stress` has no gameplay caller yet**—hazard wiring is backlog ([F1](../architecture/backlog.md)).
- `enter_unspace` snapshots hull from the assembled ship; arrival does not heal.

## Public route timing (4 / 5 / 6)

On each `routes.json` edge, `friction` applies to the **4-space** economy path. Additional `translations[]` rows add alternate N with:

- Directional `solution_ab` / `solution_ba` integers
- Optional `duration_scale` (GST entry/exit lumps = `friction × 240 × duration_scale` seconds at synthesis time)
- Optional `ease` for nav accuracy

Example: many 5-space rows use `duration_scale: 0.58`. Commodity economy still uses **4-space edges only** ([trade_network.md](trade_network.md), [commodity_economy.md](../architecture/commodity_economy.md)).

## Catalog schema

[`data/catalog/schema/unspaces.schema.json`](../../../data/catalog/schema/unspaces.schema.json) → runtime `UnspaceDef`.

Required top-level keys: `id`, `n`, `name`, `play_bounds`, `spawn`, `gst`, `field`. Optional: `orbit_name`, `objective`.

The **`field`** object is validated loosely (`additionalProperties: true` on nested objects). Expected sections used in code:

| Section | Purpose |
|---------|---------|
| `palette` | Face and portal colours |
| `topo` | Scatter, Delaunay, height scale, FOV margin |
| `portal` | Interact radius, placement fractions, interactable id |
| `inhabitants` | Ascidian counts, speeds, radii, spawn separation |

## Code map

| Area | Location |
|------|----------|
| Enter / exit / save guards | `scripts/gameplay/game_session.gd` |
| World flags and spawn | `scripts/gameplay/world_presence.gd` |
| Unspace GST pulses | `scripts/gameplay/sim_clock.gd` |
| Catalog load / `get_unspace_for_n` | `scripts/gameplay/catalog.gd` |
| Route translation synthesis | `scripts/gameplay/catalog.gd` (route load) |
| Jump UI and stability | `scripts/gameplay/translation_nav.gd`, `scripts/presentation/world_controller.gd` |
| Load field | `scripts/presentation/world_loader.gd` |
| Field mesh, portal, ascidians | `scripts/presentation/nspace_field.gd`, `nspace_backdrop_3d.gd`, `ascidian.gd` |
| Volatile mission sites | `scripts/gameplay/volatile_translation.gd`, separate world load |

## Placeholders and follow-ons

Documented gaps to close when expanding this spec:

1. **Distinct 5-space and 6-space** (and 7–9) catalog worlds and `enter_unspace` presentation selection.
2. **GST pulse tuning per N** (and/or per `unspace_world_id`).
3. **Stability and hazards** affecting ascidians, hull stress, portal rules, and geometry beyond seed inputs.
4. **Hull stress** hooked to environmental or combat sources in transit.
5. **Infinite or tiled** unspace navigation ([F1](../architecture/backlog.md), [F2](../architecture/backlog.md)).
6. **Randomised** entry spawn and exit portal placement policy (partially seeded today; backlog asks for broader randomisation).
7. **Economy** using n>4 edges—explicitly out of scope until designed ([commodity_economy.md](../architecture/commodity_economy.md)).

When behaviour or catalog shape changes, update this file in the same change as the code or JSON.
