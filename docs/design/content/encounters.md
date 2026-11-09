# Random encounters

**Status:** Framework live with one sample encounter per location class (hub, branch, volatile, Unspace).

Optional events roll when the pilot **arrives** at a place — fresh `sector_entered` or `unspace_entered`, not on save load. Default catalog chance is **10%** (`encounters.json` → `chance`). A successful roll picks one weighted definition for that location class, builds a persisted **plan** (messages, ship spawns, or ascidian extras), and publishes `SimEvent.encounter_started` for future plotlines.

## Location classes

| Class | Detection |
|-------|-----------|
| `hub` | Catalog sector whose world has a `jump_gate` |
| `branch` | Any other catalog sector (e.g. belt beacons) |
| `volatile` | Sector id `volatile:*` |
| `unspace` | `WorldPresence.in_unspace` |

Leaving clears the active plan; the next arrival rolls again with an incremented **arrival ordinal** so reloads in the same visit do not re-roll (plan is in the save).

## Catalog

[`encounters.json`](../../../data/catalog/encounters.json): root `chance`, `encounters[]` with `id`, `location_classes`, `weight`, optional `once`, `require_plotline`, optional `plugin`, and `effects[]`.

Effect kinds:

- **`message`** — `log` and optional `headline` (WIRE on hubs only when announced).
- **`spawn_ship`** — `slot`, `template_id` (omit when `callsign_from: celebrity`), `attitude` (`passive`, `hostile_player`, `hostile_peer` + `peer` slot), `transponder`, optional `callsign_from: celebrity` (binds a living pilot from `celebrity_pilots.json` and one of their signature ships; persisted plan carries `celebrity_loadout`).
- **`ascidian_cluster`** — `extra_count`, `spread_fraction` (Unspace only).

Optional **`plugin`** ids must appear in [`EncounterPlugins`](../../../scripts/gameplay/encounter_plugins.gd) and pass catalog validation.

## Runtime

[`EncounterSubsystem`](../../../scripts/gameplay/encounter_subsystem.gd) on [`Simulation`](../../../scripts/gameplay/simulation.gd): save key `encounters` (active plan, `dead_pilots`). Hub `celebrity_arrival` skips pilots marked dead; killing a pinned celebrity in flight records death immediately. [`EncounterMaterialize`](../../../scripts/gameplay/encounter_materialize.gd) builds pinned traffic actors after sector load; celebrity ships use additive hull livery per pilot. [`NspaceField.apply_encounter_ascidians`](../../../scripts/presentation/nspace_field.gd) adds extra inhabitants.

Plot arcs can listen for `encounter_started` like other [`SimEvent`](../../../scripts/gameplay/sim_event.gd) types — see [plotlines.md](plotlines.md).
