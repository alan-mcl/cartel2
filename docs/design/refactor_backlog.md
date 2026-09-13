# Engineering refactor backlog

Phased maintainability and extensibility work, written so a single item can be picked up
cold by someone (or some agent) with no other context. For deferred **design and content**
features see [backlog.md](backlog.md); for what exists in code today see
[architecture.md](architecture.md).

## How to use this file

- Work items are `P<phase>-<n>`. Lower phases first; within a phase, respect **Depends on**.
- Before starting, check **Depends on** is `Done` and no in-progress item lists the same files
  under **Scope** — parallel agents contending on `game_session.gd` or `main.gd` will conflict.
- Read **Explicitly do NOT** before writing code. Those entries record decisions that were made
  deliberately and have been "helpfully" undone before.
- Every item must satisfy **Acceptance** before being marked `Done`, including
  `./scripts/ci/check.sh`.
- Update **Status** in this file as part of the same commit as the work.

## Standing decision: the project stays on GDScript

**A port to Godot .NET/C# was assessed and rejected.** Do not propose or begin one as part of
any item here. The reasoning, briefly, so it does not get relitigated:

- Measured hot-path costs in this codebase have been algorithmic, not language-bound. The
  `perf` pass (commit `da4be82`) got its wins from caching `modules_by_category`, precomputing
  a signature basis, and using `PackedFloat32Array` — none of which C# would have made
  unnecessary.
- Godot's own guidance is that GDScript and C# are "within the same order of magnitude", that
  C# can be *slower* across heavy engine-API traffic due to marshalling, and that C# adds GC
  pause risk. This project's simulation talks to `Node2D` transforms and physics constantly.
- Godot 4.7 C# **cannot export to web at all**. Web export is being kept open.
- A hybrid C#/GDScript split is worse than either: no cross-language inheritance, untyped array
  marshalling, and string-based signal connection, exactly at the boundary we cross most.

If a genuinely language-bound hot loop ever appears after algorithmic fixes, the escape hatch is
a **GDExtension for that one kernel**, which also keeps web export working. The `ShipSimCore`
boundary in [P2-3](#p2-3-converge-player-and-npc-ship-simulation) is what would make that
possible.

---

# Phase 0 — Backlog and safety net

Phases 1-3 move persisted state and shared simulation code. The systems most likely to break
are the ones with no tests. Do Phase 0 first.

## P0-1 This backlog

**Status:** Done. **Phase:** 0.

Roadmap captured in this file and cross-linked from [backlog.md](backlog.md) and
[AGENTS.md](../../AGENTS.md).

## P0-2 Save round-trip test, `background_id` bug, validator unification

**Status:** Done. **Phase:** 0. **Depends on:** none.

**Unblocks:** [P1-3](#p1-3-save-registry-with-per-section-versioning) (save registry) and all of
Phase 2 — you cannot safely decompose `GameSession` without a round-trip test.

**Problem:** Three defects in the save path, all of the same kind: the writer and the reader of
a section lived in different files and drifted.

1. `GameSession.from_save` read `player.background_id`, but `SaveStore.build_save_data` never
   wrote it. Background was silently lost on every save/load round-trip.
2. `SaveStore.validate_save_data` and `GameSession._validate_save_data` were byte-identical
   copies, and the `SaveStore` one was **dead** — nothing called it.
3. `build_save_data` took `callsign` and `portrait_path` as loose positional strings, so adding
   a fourth identity field meant remembering to touch two files. That is what caused (1).

**Scope (done):** `GameSession.player_to_dict()` now owns serialization of the player identity
section, symmetric with `from_save` reading it. `SaveStore.build_save_data` takes that dict
instead of loose strings. `GameSession._validate_save_data` deleted in favour of
`SaveStore.validate_save_data`. Round-trip coverage in `tests/test_save.gd`.

**Explicitly do NOT:** add `GameSession` as a parameter *type* in `save_store.gd`. `GameSession`
references `SaveStore.SAVE_VERSION`, and making the dependency mutual risks a GDScript cyclic
reference error. Pass dictionaries across that boundary.

**Known gap — read before adding file-level save tests.** `tests/test_save.gd` deliberately stops
at the dictionary level and does not exercise `SaveStore.write_slot` / `read_slot`. `SAVE_DIR` is
a hardcoded `const` pointing at `user://saves/`, and there are only three fixed slot paths, so a
test that writes a slot **would overwrite the developer's real save files** every time the suite
ran. Before adding file-level coverage, make the save directory injectable (constructor argument
or an overridable static) and point tests at a temporary directory. Worth folding into
[P1-3](#p1-3-save-registry-with-per-section-versioning).

## P0-3 Tests for the untested systems Phase 1-2 will disturb

**Status:** Done. **Phase:** 0. **Depends on:** none.

**Unblocks:** Phases 1 and 2 safely.

**Problem:** `SaveStore`, `CommodityEconomy`, `GameClock`, `ShipMotion`, and `TrafficDirector`
had no direct tests, and Phase 1 rehosts the clock and economy onto a new tick model while
Phase 2 moves the traffic director between layers. All five are cheap to test — gameplay is
`RefCounted` with no scene tree, so no game boot is needed.

**Scope (done):** `tests/test_economy.gd` (quote determinism, day rollover, produce/consume
skew, sell-below-buy invariant), `tests/test_clock.gd` (GST advance, freeze, day-boundary quote
refresh, unspace pulse), `tests/test_motion.gd` (thrust, damping, speed clamp, rotation,
boost), `tests/test_save.gd` (round-trip, version gate, legacy v1 cargo migration).

**Explicitly do NOT:** add GUT or gdUnit4. Use `TestRunner` and register the suite in
`tests/run.gd`.

**Note:** `TrafficDirector` is deliberately **not** covered here — it owns scene nodes today, so
testing it headlessly means fighting the very layer violation that
[P2-2](#p2-2-move-traffic-node-ownership-out-of-the-gameplay-layer) removes. Write its tests as
part of P2-2, once the node ownership has moved and the sim half is pure.

## P0-4 Replace hardcoded SKU counts with structural invariants

**Status:** Done. **Phase:** 0. **Depends on:** none.

**Unblocks:** Content work. Every module added to `modules.json` broke the test suite.

**Problem:** `tests/test_catalog.gd` asserted exact catalog sizes (`weapons.size() == 31`, 48
propulsion, 48 power, 41 compute, and so on), and `scripts/tools/validate_catalog_refs.py`
duplicated the same constants. Adding one SKU meant editing a test and a validator that had
nothing to say about correctness.

**Scope (done):** Count assertions replaced with invariants that scale — non-empty categories,
required fields present on every entry, ids unique, referenced ammunition resolvable, mount
points valid, signature channels present and non-negative. Minimum floors kept where a category
genuinely must not regress to near-empty.

**Explicitly do NOT:** reintroduce exact-count assertions. If you need to guard against
accidental *deletion*, assert a floor (`>= 20`), not equality.

## P0-5 CI: cover test scripts, add a fast mode, add optional linting

**Status:** Done. **Phase:** 0. **Depends on:** none.

**Unblocks:** Every later phase — `check.sh` was ~77 s, which is long enough that it gets
skipped during iteration.

**Problem:** `tests/*.gd` were excluded from the `--check-only` sweep, so a parse error in a test
was only found by running it. There was no way to run a quick subset. No linter or formatter
existed.

**Scope (done):** `tests/` added to the check-only sweep. The sweep now runs one Godot process
per script **in parallel** across `nproc` (override with `--jobs N` or `CHECK_JOBS`), which is
where most of the wall-clock saving comes from — verified to detect a deliberately broken script
identically at `--jobs 1` and `--jobs 8`. Mode flags added: `--fast` (validators plus unit tests,
no import or sweep), `--scripts-only`, `--tests-only`, `--help`. Optional `gdlint` step runs when
`gdlint` is on `PATH` and is skipped with a notice otherwise, so the check never hard-depends on
`gdtoolkit` being installed.

**Explicitly do NOT:** make `gdlint` mandatory (the codebase has never been linted; it would
fail immediately). Do not trust Godot's exit code — it returns `0` on parse errors, which is why
the script greps for `SCRIPT ERROR|Parse Error|Failed to load script`. Never pair `--check-only`
with `--debug`. Do not treat `--fast` as sufficient for marking work complete.

**Note:** A GitHub Actions workflow was **not** added — this repo has no git remote configured.
Add one when a remote exists; `check.sh` is already CI-shaped (non-zero exit on any failure).

## P0-6 Dead code and documentation drift

**Status:** Done. **Phase:** 0. **Depends on:** none.

**Problem:** `scripts/ui/location_overlay.gd` (319 lines) and `scenes/location_overlay.tscn` were
the pre-`UiRoot` habitat overlay, superseded and not referenced by `main.tscn`.
[AGENTS.md](../../AGENTS.md) and [docs/README.md](../README.md) both claimed `data_model.md` was
missing or unrestored; it exists at [data_model.md](data_model.md) with 336 lines.

**Scope (done):** Dead overlay removed, doc index corrected.

**Note:** `scenes/ui/patterns/data_table.tscn` was reported missing during assessment. It
exists and is valid. No action needed.

---

# Phase 1 — Simulation kernel and event bus

The keystone phase. Today `main.gd` hand-drives every tick and the only gameplay signal is
`GameSession.changed`, so each new feature becomes a `GameSession` field plus a `main.gd` tick
block plus a `habitat_screen` match arm. This phase creates the seam that missions, factions,
plot, and off-screen simulation all plug into.

## P1-1 `SimClock` and the `Simulation` subsystem registry

**Status:** Done. **Phase:** 1. **Depends on:** P0-2, P0-3.

**Unblocks:** Missions, faction standing, overarching plot, and galaxy-wide background
simulation.

**Problem:** There is no central tick. `main._process` drives `GameClock.tick`, and
`main._physics_process` drives `TrafficDirector.tick` plus nav contact assembly plus sensor HUD
updates. Anything needing time has to be wired into a presentation node by hand. There is
nowhere to put a system that ticks once per in-game day across all sectors.

**Scope:**
- New `scripts/gameplay/sim_clock.gd`: owns GST, emits ticks at frame, in-game hour, and
  in-game day granularity. Absorbs `game_clock.gd`, including its unspace pulse and freeze
  behaviour.
- New `scripts/gameplay/sim_subsystem.gd`: the contract — `id`, `on_tick(dt)`, `on_day(day)`,
  `on_event(evt)`, `to_dict()`, `from_dict()`. All optional except `id`.
- New `scripts/gameplay/simulation.gd`: owns the registry and the clock, stepped **once** from
  `main.gd`.
- Migrate `CommodityEconomy` and the calendar onto it.

**Design note:** Off-screen sector simulation is the motivating use case and it should be a
subsystem implementing **only** `on_day`. Coarse, low-frequency, statistical updates for
sectors the player is not in — not per-frame actors. The existing traffic LOD design (20 sim
slots out of ~100 actors) is the right instinct applied at the wrong scale; this generalises it.

**Explicitly do NOT:** make subsystems `Node`s, and do not let `Simulation` touch the scene
tree. Gameplay stays `RefCounted`.

**Acceptance:** `check.sh` passes. `main.gd` contains exactly one simulation step call. Economy
and calendar behaviour unchanged — `tests/test_economy.gd` and `tests/test_clock.gd` pass
untouched.

## P1-2 Typed event bus

**Status:** Done. **Phase:** 1. **Depends on:** P1-1.

**Unblocks:** Mission triggers, faction reputation deltas, plot state advancement. This is the
single most important item for the mission system.

**Problem:** `signal changed` in `game_session.gd` is the entire gameplay event vocabulary,
emitted from ~50 sites between `GameSession` and `ShipAssembly`, and every emission triggers a
full UI rebuild. A mission cannot ask "did the player just sell contraband in Proxima" — the
information does not exist by the time the signal arrives.

**Scope:** A typed event bus with a concrete event vocabulary — at minimum `SectorEntered`,
`Docked`, `Undocked`, `CommodityTraded`, `ShipPurchased`, `ModuleInstalled`, `CreditsChanged`,
`ShipDestroyed`, `SalvageTaken`. Publishers replace bare `changed.emit()`. UI subscribes to what
it needs.

**Explicitly do NOT:** delete `changed` in this item. Keep it as a coarse "something changed"
fallback so UI migration can be incremental, and remove it only once no subscriber is left.

**Acceptance:** `check.sh` passes. Trading a commodity emits a `CommodityTraded` carrying
sector, commodity, quantity, and unit price. HUD and habitat screens still refresh correctly.

## P1-3 Save registry with per-section versioning

**Status:** Done. **Phase:** 1. **Depends on:** P1-1, P0-2.

**Unblocks:** Persisting mission progress, faction standing, and plot state without a central
edit each time.

**Problem:** Serialization is hand-written `to_dict`/`from_dict` assembled centrally, which is
what produced all three P0-2 defects. Every new persisted field means editing the writer, the
reader, and the validator. `ShipCombatState` already has a `from_dict` that persistence does not
use, and combat state is instead flattened onto session scalars.

**Scope:** Sections keyed by subsystem `id`, each versioned independently, collected by
iterating the registry rather than by a central literal. Migration hooks per section.

**Explicitly do NOT:** break existing saves without a migration path. `SAVE_VERSION` is 2 and v1
legacy cargo migration must keep working — `tests/test_save.gd` covers it.

## P1-4 Mission system spike

**Status:** Done. **Phase:** 1. **Depends on:** P1-1, P1-2, P1-3.

**Problem:** The quest system today is `var objective: String`.

**Scope:** One hardcoded delivery mission — accept, track via `CommodityTraded` and
`SectorEntered`, complete, pay out, persist across save/load. The point is to prove the three
seams work end to end **before** content is built on them.

**Explicitly do NOT:** build mission catalog JSON, a mission board UI, or a mission type
taxonomy in this item. It is a spike; keep it to one hardcoded mission.

---

# Phase 2 — Decompose `GameSession`, fix layer violations

## P2-1 Split `GameSession`

**Status:** Done. **Phase:** 2. **Depends on:** P1-1, P1-2, P0-2, P0-3.

**Problem:** 971 lines spanning player identity, location and unspace transit, wallet, spare
parts, market quote cache, fleet, persisted combat hull state, GST, and orbital phase. It is
both the mutation hub and the persistence root, so every feature lands here.

**Scope:** `PlayerState`, `WorldPresence`, `Fleet`, `Wallet`, `CombatPersistence`, with
`GameSession` as a thin aggregate root. Also extract the credits-check → `last_log` → emit
transaction boilerplate repeated across ~50 sites in `GameSession` and `ShipAssembly`.

**Explicitly do NOT:** change behaviour in this item. It is a pure move. `tests/test_session.gd`
and `tests/test_save.gd` should pass with only mechanical reference updates.

## P2-2 Move traffic node ownership out of the gameplay layer

**Status:** Done. **Phase:** 2. **Depends on:** P1-1.

**Unblocks:** Headless `TrafficDirector` tests (deferred from P0-3), and combat build-out.

**Problem:** `scripts/gameplay/traffic_director.gd` violates the repo's own `RefCounted`-only
rule for gameplay: it calls `Node2D.new()`, `add_child`, `queue_free`, and
`load("res://scenes/npc_ship.tscn")`, imports presentation scripts (`ChassisSprite`,
`HullHitbox`), and reads `Engine.get_physics_frames()` for detection stagger.

**Scope:** Split into a pure spawn/LOD/sim-slot policy in `scripts/gameplay/` and a node
lifecycle owner in `scripts/presentation/`. `TrafficActor` keeps its simulation but loses its
`node: Node2D` field in favour of an opaque handle owned by presentation. Add the deferred
`TrafficDirector` tests once the sim half is pure.

**Explicitly do NOT:** change LOD radii, sim slot counts, or the detection stagger cadence.
Re-run `scripts/dev/bench_traffic.gd` before and after and keep the numbers within noise.

## P2-3 Converge player and NPC ship simulation

**Status:** Done. **Phase:** 2. **Depends on:** P1-1.

**Unblocks:** Combat systems build-out. A new weapon class currently has to be implemented
twice.

**Problem:** `player_ship.gd` runs the full ops/combat/sensor/weapon simulation inline in
`_physics_process`, while `npc_ship.gd` is an 8-line view (`sync_from_actor()`) over a
simulation living in `traffic_actor.gd`. The two have **forked implementations of the same
rules** — weapon order spawning is ~95% duplicated (~55 lines each), as are hull visual setup,
damage tint, and muzzle offset.

**Scope:** One `ShipSimCore` holding the shared rules, consumed by both. Each recompute is a
separately callable step (`step_physics`, `step_operating`, `refresh_signature`,
`refresh_stats`) making no assumption about who calls what when. Nodes become input plus view.

**Explicitly do NOT — read this before touching cadence:** the player and NPCs **should** update
at different frequencies, and that difference is a requirement, not a bug.

- The player needs live signature and operating telemetry every frame because the HUD displays
  it, even where it has no gameplay effect today. An NPC at far LOD does not.
- Converge the code path; keep the frequencies independent. Cadence belongs in an explicit
  policy on the owner — player controller at display rate, traffic director at its existing sim
  slot and LOD rates.
- Make the difference legible at both call sites (a named cadence policy, or a comment saying
  why) so this does not get "fixed" later.
- Do **not** put `ShipAssembler.calculate_loaded_mass` and `derive_stats` behind a simple dirty
  flag. Loaded mass changes continuously as fuel burns, so a dirty flag either never fires or
  fires every frame. Use a change threshold, or a lower fixed cadence for NPCs, while leaving
  the player on the per-frame path if the HUD needs it.

**Acceptance:** `check.sh` passes. `bench_traffic.gd` `mass + derive_stats (sim actors)` and
`actor.tick full sim` do not regress. Player flight feel unchanged. HUD signature readout still
updates every frame.

## P2-4 Split `main.gd`

**Status:** Done. **Phase:** 2. **Depends on:** P1-1, P1-2.

**Problem:** 675 lines and the second-most-churned file in the repo (23 commits). It owns
session lifecycle, world loading, traffic ticking, nav and HUD feeding, save/load, input and
pause gating, jump/unspace transitions, and interaction routing. `_physics_process` alone mixes
traffic, nav contacts, and sensor HUD updates.

**Scope:** `FlightLoopController`, `WorldController`, `MenuController`. Target ~150 lines of
wiring in `main.gd`.

## P2-5 Boundary and per-frame correctness fixes

**Status:** Done. **Phase:** 2. **Depends on:** none (can run parallel to P2-1).

**Scope:** Small, independent fixes:
- `debris_rock.gd` holds combat HP (`DEFAULT_HP := 40.0`) and death logic in presentation — move
  the rule to gameplay.
- `orbital_ring.gd` writes `session.set_orbital_phase()` from `_process`. Invert it: the
  simulation owns phase, presentation reads it for rotation.
- `WorldLoader.get_nav_contacts` `.duplicate()`s every cached entry on every call, and `main`
  calls it every physics frame. Mutate in place and hand out a read-only view.
- Replace `get_parent().session` in `player_ship.gd` and `main.get("session")` duck-typing in
  `follow_camera.gd` with injected references.

## P2-6 Split `traffic_actor.gd`

**Status:** Done. **Phase:** 2. **Depends on:** P2-2, P2-3.

**Problem:** 1,385 lines — the largest file in the repo — mixing AI state machines, routing,
detection staging, and motion, with deep nesting. `combat_pilot.gd` (779 lines) has the same
shape.

**Explicitly do NOT:** rewrite the AI. Traffic and combat are the best-tested systems here
(`test_combat.gd` is 987 lines, `test_sensors.gd` 612). Split along seams; preserve behaviour.

---

# Phase 3 — Typed content records

## P3-1 Schema-driven catalog records and validation

**Status:** Done. **Phase:** 3. **Depends on:** P0-4.

**Unblocks:** The largest single win for agent-authored code correctness.

**Problem:** The catalog never materialises typed content — `catalog.get_module(id)` returns a
raw `Dictionary`, and there are ~361 `Dictionary` references in the gameplay layer. A typo like
`module.get("thurst", 0.0)` silently yields `0.0` forever, with no parse error, no test failure,
and no runtime warning. Separately, `scripts/tools/validate_catalog_refs.py` is ~770 lines of
hand-written per-category rules that must be kept in sync with the JSON by hand.

**Scope:** Define the catalog schema once, machine-readably. Generate from it: typed GDScript
record classes (`ModuleDef`, `ChassisDef`, `ShipDef`, `SectorDef`, `WorldDef`), the validator,
and schema documentation. Materialise records once at load.

**Explicitly do NOT:** attempt all catalog types in one pass. Ship it incrementally, and see
P3-2 for the order.

## P3-2 Migrate `modules.json` first

**Status:** Done. **Phase:** 3. **Depends on:** P3-1.

**Problem:** 271 entries, 158 KB, hand-authored, 14 commits of churn, maintained by a mix of
manual editing and one-off scripts (`generate_combat_catalog.py`,
`patch_module_signatures.py`). It is the worst offender on every axis.

**Scope:** `ModuleDef` records first, then chassis, ships, sectors, worlds. Either split
`modules.json` by category or formalise the generators — stop hand-editing 158 KB.

## P3-3 Close the unvalidated reference edges

**Status:** Done. **Phase:** 3. **Depends on:** none.

**Scope:** `economies.json` `produce`/`consume` keys are never checked against
`commodities.json`, so a typo fails silently at quote time. Also resolve `markets.json`, which
is an empty `[]` stub with a dead `Catalog.get_market_for_building()` path.

**Note:** the `habitats.json` → `buildings.json` edge is covered by
[P4-2](#p4-2-sector-completeness-validator). Do it in whichever lands first, not twice.

---

# Phase 4 — Content throughput and screen registry

Framing note: outlying areas — moons, mining sectors — are **ordinary sectors** in the existing
catalog. The variation is cosmetic: art, `modulate`, orbital count, traffic mix, flavour text.
The goal of this phase is that adding the 50th sector costs what adding the 12th did.

## P4-1 Sector bundle generator

**Status:** Done. **Phase:** 4. **Depends on:** P4-2 (validator first, so the generator
has a correctness oracle).

**Problem:** A sector is one logical unit stored across six files with hand-matched ids. Adding
one means coordinated entries in `sectors.json`, `worlds.json`, `economies.json`,
`habitats.json`, plus ~3 buildings, 2 interactables (`<id>_habitat`, `<id>_jump_gate`), 3-9
routes, and traffic weights. All 11 existing sectors follow the pattern identically.

**Scope:** A generator in `scripts/tools/` taking a compact per-sector spec — id, name, star
system, classification, population, climate, planet art and `modulate`, orbital list, economy
tier and produce/consume, habitat buildings, route links — and emitting or patching all seven
files.

**Explicitly do NOT:** introduce new world or location *types*, a layout registry, or new
`kind` values for moons and mining. They are planetary sectors with different art. Leave
`WorldLoader`'s `has("planet")` branch and `SCENES` dict alone.

## P4-2 Sector completeness validator

**Status:** Done. **Phase:** 4. **Depends on:** none. **Can be pulled into Phase 0** if
sector authoring starts before this phase — it is cheap and independently valuable.

**Problem:** Nothing verifies that a sector is complete across the six files it spans.

**Scope:** For every id in `sectors.json` assert a matching world, economy, and habitat; that
habitat buildings all resolve in `buildings.json`; that `<id>_habitat` and `<id>_jump_gate`
interactables exist and are referenced by the world entry; and that the sector has at least one
route. Add to `validate_catalog_refs.py` or a sibling script wired into `check.sh`.

## P4-3 Building type to panel registry

**Status:** Done. **Phase:** 4. **Depends on:** P1-2.

**Unblocks:** Comms panel, mission board, and the currently-empty `bar` building type (its
`_rebuild_content` match arm falls through to `pass`, rendering a blank pane).

**Problem:** New screens are added by growing a `match` on building type inside
`habitat_screen.gd`. `ScreenStack.push_screen` exists but is unused in production.

## P4-4 Parameterise the unspace field

**Status:** Not started. **Phase:** 4. **Depends on:** P3-1.

**Problem:** `unspaces.json` has exactly one entry (n=4) and `NspaceField` builds the field from
procedural constants, so deeper layers are code rather than content.

**Explicitly do NOT:** wire n>5 routes or hyperdrive translation as part of this. The
[AGENTS.md](../../AGENTS.md) scope guardrail stands — this item makes the data-driven field
possible, it is not permission to enable deeper layers.

## P4-5 Decide the fate of the unused world entity kinds

**Status:** Not started. **Phase:** 4.

**Problem:** `WorldLoader.SCENES` registers `beacon`, `wreck`, `debris`, and `hazard`, with
scenes and scripts behind them, but no catalog JSON references any of them. Either use them as
outlying-area flavour or delete the dead path.

---

# Phase 5 — UI decomposition

## P5-1 Split `habitat_screen.gd`

**Status:** Not started. **Phase:** 5. **Depends on:** P4-3.

**Problem:** 969 lines acting as building router plus four embedded sub-UIs (terminal, market,
ship dealer, chassis dealer). Two known leaks: it calls `CommodityEconomy.sell_price` directly
for display, and constructs `OwnedShip.from_template()` for dealer previews.

**Scope:** Thin router plus `TerminalPanel`, `MarketPanel`, `DealerPanel`.

## P5-2 Shared `ShipDetailPanel`

**Status:** Not started. **Phase:** 5. **Depends on:** P5-1.

**Problem:** The habitat terminal and the shipyard render overlapping module list, engineering,
and signature views through separate code, both calling `ShipAssembly`.

## P5-3 Adopt the pattern components that already exist

**Status:** Not started. **Phase:** 5.

**Problem:** `scenes/ui/patterns/` contains `metric_block`, `status_row`, `headline_item`,
`alert_banner`, `compact_toolbar`, and `data_table` — all instantiated **only** by
`scenes/dev/theme_showcase.tscn`. Meanwhile production screens hand-roll ~600 lines of
programmatic layout and reimplement `_section_label` and `_detail_row` identically in two files.
The design system is ahead of the screens.

**Scope:** Use the patterns in production screens. Move shipyard's ~70-line `_stock_meta()`
category formatting into `ModuleSpecText`. Replace `hud.gd`'s runtime `StyleBoxFlat` with a theme
variation.

## P5-4 Screen base class

**Status:** Not started. **Phase:** 5. **Depends on:** P4-3.

**Scope:** A base with `bind(context)` / `refresh()` / `handle_back()` so "add a screen" is a
recipe rather than four unrelated edits.

---

# Phase 6 — Presentation dedup and pooling

## P6-1 Shared ship visual adapter

**Status:** Not started. **Phase:** 6. **Depends on:** P2-3.

**Scope:** Hull visual setup, damage tint, weapon order spawning, and muzzle offset are ~110
duplicated lines between `player_ship.gd` and `npc_ship.gd`. Extract once P2-3 has unified the
simulation side.

## P6-2 `FlightSandboxBase`

**Status:** Not started. **Phase:** 6. **Depends on:** P2-4.

**Problem:** `combat_sandbox.gd` (532 lines) and `stealth_sandbox.gd` (616 lines) are parallel
mini-`main` implementations that drift whenever `main.gd` changes.

## P6-3 Object pooling

**Status:** Not started. **Phase:** 6. **Depends on:** P2-2.

**Problem:** No pooling anywhere. `TrafficDirector._update_lod_node` `queue_free`s and
re-instantiates a node on **every** near/far LOD crossing, and projectiles instantiate and free
per shot.

**Explicitly do NOT:** do this before measuring. Pool only what `bench_traffic.gd` and a frame
profile show to matter, and note that `_sim_slot_pool` in `traffic_director.gd` is a priority
queue for sim slots, not an object pool — the name is misleading.
