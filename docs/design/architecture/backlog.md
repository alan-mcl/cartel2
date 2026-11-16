# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

Implemented N-space transit, hazards, and per-N backdrops are documented in [n-space.md](../content/n-space.md) (flux, folds, shards, ascidian scan/sting/shed/fold/terrain flow). Do not edit frozen setting files for backlog items unless the request explicitly asks for setting-doc changes.

**Refactoring** items (R2–R15) are structural debt from the November 2026 review. Pick one id at a time. Read **Depends on** and **Do not** before editing. Content features F3, F10, and F2 stay in the feature table; their structural prerequisites are R3, R4, and R6.

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B6 | missions | med | bounty target "run away" behaviour isn't fun, should be reworked |
|B1|data|med|Double 'Janus' in the planets catalog|

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F3|gameplay|med|Plotlines: implementations now that the framework is there. Desk wiring is R3|
|F9|modules|med|Scatter cannon: tighten the spread and increase the range a bit|
|F10|npc|med|NPC pilots to use hyperdrives if equipped. Escape path is R4|
|F1|art|low|irregularly shaped planet renderer (for comets, KBOs, etc)|
|F2|systems|med|asteroid/debris placement around maps and vectors. Spawn registration is R6|

## Refactoring

Structural work only. Suggested order when nothing else forces a choice: R14, R15, and R11 are small and independent; then R3 (shared charter lifecycle is landed); R4 before F10; R5 before R6; R7 before R8. R9, R10, R12, and R13 can land any time.

| ID | Area | Sev | Desc |
|----|------|-----|------|
|R3|missions|high|Plotline gigs reachable from a desk, plus a charter-complete event. Unblocks F3|
|R4|flight|high|Bounty escape and Unspace hull stress live in gameplay. Unblocks F10|
|R5|world|high|Traffic and encounters query anchors without constructing WorldLoader|
|R6|world|high|Register entity kinds instead of private spawn branches. Unblocks F2|
|R7|session|high|Travel, dock, cargo, and trade move onto the state slices|
|R8|session|high|Call sites use the slices; forwarding properties stay until that is done|
|R9|data|med|Schema checks for worlds, buildings, traffic, and interactables|
|R10|data|med|One chassis source on AssembledShip; typed getters stop rebuilding dictionaries|
|R11|save|med|Save doc matches version 3; mission migration is tested; future subsystem versions fail closed|
|R12|ui|med|One soft-refresh helper for the dock desks|
|R13|dev|med|Combat and stealth sandboxes run the production NPC loop|
|R14|tests|med|Sensor suite stops requiring exactly 11 SKUs|
|R15|docs|med|Player hyperdrive is documented as implemented; NPC use stays F10|

### R3 — Plotline desk hook

- **Status:** Discuss
- **Depends on:** —
- **Unblocks:** F3
- **Scope:** `scripts/gameplay/plotline_subsystem.gd`, `scripts/gameplay/mission_subsystem.gd`, `scripts/gameplay/sim_event.gd`, the desk UI that will list gigs, `tests/test_plotlines.gd`
- **Do not:** author arcs in `plotlines.json` (F3); invent setting lore; persist a new save shape without a migrate test
- **Acceptance:** completing any of the five charter kinds publishes a charter-complete `SimEvent`. A production desk calls `list_plot_gigs` and `accept_gig` / `complete_gig`. An empty `plotlines.json` still loads. Tests cover the event and a gig accepted outside the unit-test-only path.

### R4 — Flight rules out of the presentation tick

- **Status:** Discuss
- **Depends on:** —
- **Unblocks:** F10
- **Scope:** `scripts/presentation/flight_loop_controller.gd`, `scripts/gameplay/mission_subsystem.gd` (`notify_bounty_ship_escaped`), Unspace hazard types, bounty tests
- **Do not:** implement NPC `Hyperdrive.spool_block` (F10); pool projectiles; rewrite `nspace_field.gd` rendering; require `class_name TrafficActor` unless the escape result cannot be typed without breaking the `traffic_routing.gd` preload cycle
- **Acceptance:** the flight loop calls gameplay for bounty escape completion and for Unspace hull stress. The three copied stress-then-destroy blocks become one gameplay function. A headless test covers escape notification and stress application without `FlightLoopController`.

### R5 — World queries without WorldLoader

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/gameplay/traffic_director.gd`, `scripts/gameplay/traffic_actor.gd`, `scripts/gameplay/traffic_routing.gd`, `scripts/gameplay/encounter_materialize.gd`, `scripts/presentation/world_loader.gd`, `tests/test_traffic.gd`
- **Do not:** move planet, star, or sky rendering into gameplay; change anchor positions or spawn counts
- **Acceptance:** gameplay takes a small `RefCounted` query (anchors, launch position, gate approach, arrival, envelope radius) instead of `WorldLoader`. `TestTraffic` does not construct `WorldLoader`. Rendering stays in presentation.

### R6 — Entity spawn registration

- **Status:** Discuss
- **Depends on:** R5
- **Unblocks:** F2
- **Scope:** `scripts/presentation/world_loader.gd`, `scripts/presentation/world_nav.gd`, `scenes/world/`
- **Do not:** place asteroid belts or vectors (F2); fold planets, local stars, or sky parent bodies into the entity registry; split `nspace_field.gd`
- **Acceptance:** a new `entities[]` kind is a scene plus a registry entry, and sensor contacts for that kind are registered beside it. `load_sector` no longer grows a private branch for that kind. Existing habitats, gates, debris, orbitals, derelicts, cargo, markers, and mines still spawn.

### R7 — Session transitions on the state slices

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/gameplay/game_session.gd`, `scripts/gameplay/world_presence.gd`, `scripts/gameplay/player_state.gd`, fleet and wallet types, `tests/test_session.gd`, `tests/test_save.gd`
- **Do not:** delete the forwarding properties (R8); change save JSON keys; change price, cargo, or travel rules
- **Acceptance:** sector travel, Unspace enter and arrive, dock, undock, cargo checks, and commodity buy/sell are methods on the types that own the state. `GameSession` forwards to them. Round-trip saves and session tests pass without a version bump.

### R8 — Call sites use the slices

- **Status:** Discuss
- **Depends on:** R7
- **Scope:** facade reads and writes under `scripts/gameplay/`, then `scripts/presentation/`, then `scripts/ui/`
- **Do not:** change behaviour; delete a forwarding property until gameplay, presentation, and UI no longer use it; mix this with rule changes
- **Acceptance:** each batch is behaviour-neutral and leaves `./scripts/ci/check.sh` green. New call sites use `session.player`, `session.world`, `session.fleet`, `session.wallet`, or `session.combat`. Forwarding properties remain until a final batch finds no remaining readers.

### R9 — Schema checks for large catalogs

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/tools/validate_catalog_refs.py` and, if a generated schema is the smaller path, `data/catalog/schema/` plus `scripts/tools/generate_catalog_records.py`. Targets: `worlds.json`, `buildings.json`, `traffic.json`, `interactables.json`
- **Do not:** generate `*Def` classes for missions, plotlines, or encounters; convert gameplay readers off dictionaries; invent fields the JSON does not already use
- **Acceptance:** an unknown key or a broken reference in those four files fails CI. `traffic.json` is checked for more than affiliation kind. Existing catalogs pass.

### R10 — Typed chassis access

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/gameplay/catalog.gd` dictionary getters that `to_dict()` a record, `scripts/gameplay/assembled_ship.gd`
- **Do not:** type buildings, worlds, or missions (R9 covers validation only); change fitting rules
- **Acceptance:** `AssembledShip` has one chassis source of truth. Gameplay reads `get_*_def` for types that already have a record. Dictionary copies happen at a library or UI boundary, not on every lookup. Assembler and catalog tests pass.

### R11 — Save contract

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `docs/design/architecture/data_model.md`, `scripts/gameplay/simulation.gd`, `scripts/gameplay/mission_subsystem.gd` `migrate`, `tests/test_save.gd`
- **Do not:** persist Unspace flux, folds, shards, or ascidian hazards; bump `SAVE_VERSION` unless the envelope shape changes; wipe accepted contracts
- **Acceptance:** the data-model save section matches envelope version 3 and the `subsystems` blob. A test loads a mission section from an older `save_version` and asserts that offer boards clear when the migrate says they clear, and that accepted contracts remain. A subsystem `from_version` newer than the code fails closed.

### R12 — Shared dock soft-refresh

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/ui/market_panel.gd`, `scripts/ui/dealer_panel.gd`, `scripts/ui/terminal_panel.gd`, `scripts/ui/shipyard_screen.gd`, `scripts/ui/corporate_office_panel.gd`, `scripts/ui/habitat_screen.gd`, `scripts/ui/ui_patterns.gd` or a neighbour
- **Do not:** redesign the desks; change prices, fitting, or charter acceptance
- **Acceptance:** soft refresh, meta-host lookup, and select-by-id live in one helper used by those desks. One `session.changed` refreshes an embedded habitat panel once. The `session.visit` re-entry guard still prevents a recursive rebuild.

### R13 — Sandboxes use the production NPC loop

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/dev/combat_sandbox.gd`, `scripts/dev/flight_sandbox_base.gd`, `scripts/dev/stealth_sandbox.gd`, `scripts/presentation/flight_loop_controller.gd`, `scripts/presentation/traffic_view.gd`
- **Do not:** change detection, weapon, or traffic rules; spawn a second body for the same actor
- **Acceptance:** the combat sandbox draws opponents through `TrafficView`. The stealth sandbox advances NPCs with `FlightLoopController.physics_tick`. A signature or weapon change on the director shows up in both drills.

### R14 — Sensor catalog assertion

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `tests/test_sensors.gd` (exact `sensors.size() == 11`)
- **Do not:** add or remove sensor SKUs; pin a new exact count
- **Acceptance:** the suite uses a floor or another structural invariant, matching `tests/test_catalog.gd`. Adding a sensor SKU does not fail the test.

### R15 — Hyperdrive docs match the player spool

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `docs/design/architecture/architecture.md` (gate-less hyperdrive “not implemented”), `docs/design/architecture/data_model.md` (hyperdrive translation still outstanding), `docs/design/content/equipment.md` (“hyperdrive translation remains planned”)
- **Do not:** implement NPC hyperdrives (F10); edit frozen setting files
- **Acceptance:** those passages describe the player spool, overlay, and `HyperdriveSolution.advance` as implemented. NPC use stays outstanding and points at F10.

## Addenda

### Unused celebrity pilot and ship names

Cuno - Doomed Commercial Venture
The Accountant
Public Enemy
Xenocyte
Marty - Easy Street

Ladbroke Grove
Long On Gravitas
Paper Tiger
Any Given Sunday
No Future
Unfinished Business
Kodak Moment
Glory to Arstotzka

