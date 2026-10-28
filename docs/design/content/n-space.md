# N-space and Unspace transit

**Status:** Playable 4–9-space transit with per-layer catalog presentation worlds (`n4_default` … `n9_default`). Public routes list **4-space**, **5-space**, and **6-space** translations only; **7–9** appear from the translation library (private strip on the jump overlay). Session state, HUD labels, and route seeding use the **real** translation N; `enter_unspace` loads `get_unspace_for_n(n)`. See [translations.md](translations.md) for jump selection, accuracy, and stability; [gst.md](gst.md) for clock behaviour; [field_conditions.md](field_conditions.md) for ambient fields in transit.

Setting vocabulary (Unspace, layers, solutions) is in [overview.md](../../setting/overview.md). This document is the **implementation spec** for what the Godot build does today and what remains placeholder.

## Terminology

| Term | Meaning in code |
|------|-----------------|
| **3-space** | Normal sector orbit play (`WorldLoader.load_sector`). |
| **N-space / Unspace** | Higher-order translation layers used for inter-sector travel (`WorldPresence.in_unspace`). |
| **Translation N** | The layer encoded on the chosen route mapping (`mapping.n`). Stored as `WorldPresence.unspace_n` for the whole crossing. |
| **Presentation world** | Catalog unspace record loaded by `WorldLoader.load_unspace` (`WorldPresence.unspace_world_id`). Matches translation N when a catalog row exists. |
| **Solution** | Integer identifying a stored mapping; seeds field geometry and portal placement (`WorldPresence.unspace_solution`). |

## Layer catalogue (current)

| Translation N | Route data | Nav computer tier (typical) | Transit presentation |
|---------------|------------|----------------------------|----------------------|
| **4** | Every public edge; beacons offer 4-space only | Always loaded from current sector | `unspaces.json` → `n4_default` |
| **5** | Subset of edges with extra `translations[]` entries | Loaded when `nav_rating` ≥ 55 (subject to capacity) | `n5_default` |
| **6** | Subset of edges (often alongside 4 and 5) | Loaded when `nav_rating` ≥ 65 | `n6_default` |
| **7–9** | Not in public routes | Translation library or hyperdrive calculation | `n7_default` … `n9_default` when entered |

[`unspaces.json`](../../../data/catalog/unspaces.json) holds one row per implemented N (4–9). `Catalog.get_unspace_for_n(n)` returns the entry whose `n` field matches.

[`worlds.json`](../../../data/catalog/worlds.json) keys each unspace id (`n4_default` … `n9_default` have empty `entities` lists). Unspace layout lives in `unspaces.json` **`field`** blocks, not in world entity lists.

## Session state while in transit

Persisted on `WorldPresence` (facaded on `GameSession`):

| Field | Role |
|-------|------|
| `in_unspace` | True from successful `enter_unspace` until `arrive_from_unspace`. |
| `unspace_n` | Translation layer for this jump (4–9 when supported). |
| `unspace_world_id` | Presentation catalog id (`n{n}_default` for the crossing). |
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
5. `WorldLoader.load_unspace` builds `NspaceField` from `unspace_world_id` (catalog row for translation N).
6. Player placed at catalog spawn (`unspaces.json` `spawn`, defaulting near `-0.45 × play_bounds` on X).

**Mapping resolution order:** `catalog.get_translation(sector, solution)` → volatile resolver → `get_public_translation(sector, destination, n)`.

**Presentation vs translation N:** `enter_unspace` sets `presentation_n := n` and loads `get_unspace_for_n(presentation_n)` (falls back to 4-space row only if no row exists). Translation N affects labels, per-row GST tuning in catalog data, stability roll inputs, backdrop parameters, and `_derive_route_seed(solution, n, salt)` for the field mesh.

**Volatile outbound:** Consumes the outbound hop when leaving a non-volatile source; destination may be a minimal volatile sector (separate loader path on arrival—not the shared N-space field).

## Transit field (`NspaceField`)

Implemented in `scripts/presentation/nspace_field.gd`, configured from the catalog **`field`** object:

### Topology

- Poisson-scattered vertices inside a play disc (`play_bounds`, default **8000**).
- Delaunay triangulation with optional convex **quad merges** (`quad_merge_chance`).
- Independent random **heights** per vertex; 2D motion uses normal ship physics; heights feed **3D backdrop** only (no terrain collision or thrust from the mesh).
- Vertex count scales with viewport FOV margin (`fov_vertex_count`, `scatter_margin`, `vertex_count_min` / `max`). Higher N uses denser meshes and lower quad-merge chance.

### Route seeding

`route_seed = hash("%d:%d:%d" % [solution, n, seed_salt])` drives RNG for scatter, portal face choice, and face colours. Same solution and N → same field layout; different N on the same edge → different layout even when presentation ids differ.

### Exit portal

- One host face chosen at configure time: centroid in an annulus (`origin_min_fraction`–`origin_max_fraction` of `play_bounds`), away from entry spawn hint (`spawn_separation_fraction`), scored with `score_spawn_weight`.
- Interactable id `unspace_exit` (requires **`4_space_topology`** sensor capability for nav labelling).
- 3D disc in `NspaceBackdrop3D`; 2D `Area2D` for `[E]` interact.

### Ascidians

- Count scales with N on each catalog row (`inhabitants` block); spawn uses visit RNG (not route seed), wander within `wander_radius_fraction × play_bounds`.
- Radar contacts as `ascidian_*`; behaviour in `scripts/presentation/ascidian.gd`.
- **Flux (F5):** short turbulence storms from `UnspaceFlux` — hull stress, velocity kick, strobing N-space palette on the topo backdrop, and an electrified hull overlay on the player ship; rate scales with `UnspaceInstability` (stability and N). Folds, shards, and ascidian hazard behaviour remain backlog ([F6–F8](../architecture/backlog.md)).

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

`SimClock` uses the loaded presentation world’s `gst` block (`unspaces.json`). Each N row carries its own pulse, stretch, and slip ranges (harsher at higher N).

- Real time advances in **pulses** with random interval (`pulse_min`–`pulse_max`), stretch factor (`stretch_min`–`stretch_max`), and optional **slips** (`slip_chance`, `slip_min`–`slip_max`).
- Menu/jump overlay **freezes** GST; pause resets unspace pulse state via `reset_unspace_pulse`.

## Field conditions and propulsion

When `in_unspace`, `FieldConditions` uses the fixed Unspace profile (low fluctuating G ~0.005–0.03, low radiant, fluctuating magnetic and particle indices)—see [field_conditions.md](field_conditions.md).

Gravitic and sail drives respond to those samples; other engines ignore local fields.

## Combat and hull

- Shots in Unspace do not record lawful-fire sanctions yet ([missions.md](missions.md)).
- `CombatPersistence.apply_hull_stress` decrements hull only while `in_unspace` (cooldown **0.45** s). **N-space flux** calls it during active storms ([`unspace_flux.gd`](../../../scripts/gameplay/unspace_flux.gd)).
- `enter_unspace` snapshots hull from the assembled ship; arrival does not heal.

## Public route timing (4 / 5 / 6)

On each `routes.json` edge, `friction` applies to the **4-space** economy path. Additional `translations[]` rows add alternate N with directional `solution_ab` / `solution_ba` integers and optional `ease` for nav accuracy.

Synthesised GST entry/exit lumps use `duration_scale(n) = 0.1 ^ ((n - 4) / 5)` (4-space scale **1**). Commodity economy still uses **4-space edges only** ([trade_network.md](trade_network.md), [commodity_economy.md](../architecture/commodity_economy.md)).

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
| Instability / flux hazards | `scripts/gameplay/unspace_instability.gd`, `unspace_flux.gd` |

## Placeholders and follow-ons

Documented gaps to close when expanding this spec:

1. **Folds, shards, and ascidian hazards** ([F6–F8](../architecture/backlog.md)).
2. **Hull stress** from shards and ascidian scans (flux wired in F5).
3. **Infinite or tiled** unspace navigation ([F1](../architecture/backlog.md), [F2](../architecture/backlog.md)).
4. **Randomised** entry spawn and exit portal placement policy (partially seeded today; backlog asks for broader randomisation).
5. **Economy** using n>4 edges—explicitly out of scope until designed ([commodity_economy.md](../architecture/commodity_economy.md)).

When behaviour or catalog shape changes, update this file in the same change as the code or JSON.
