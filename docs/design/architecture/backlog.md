# Backlog

Single list of open work. Completed engineering phases 0–6, and the constraints that must not be undone, stay in [refactor_backlog.md](refactor_backlog.md). Do not add new items there.

Nothing in this file is approved work. Status stays **Discuss** until it is picked up. When an item is picked up, set **Status** to `In progress` then `Done` in the same change as the work, and run `./scripts/ci/check.sh` before marking it done.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

## How to read an item

- **Severity** is how much it will hurt the next feature or the next content drop, not a schedule.
- **Direction** is a starting point for discussion, not a design sign-off.
- **Do not** records decisions that have already been made. Do not reverse them while picking up a nearby item.

## Standing decisions

Copied here so this file can be used without re-reading the archive. The reasoning lives in [refactor_backlog.md](refactor_backlog.md).

- The project stays on GDScript. A C# port was assessed and rejected. A language-bound hot loop, if one ever remains after algorithmic fixes, would be a GDExtension for that kernel.
- Gameplay stays `RefCounted`. No scene tree, no `@onready`.
- Do not add `GameSession` forwarding properties. Call `session.player`, `session.world`, `session.fleet`, `session.wallet`, or `session.combat`.
- Player and NPC ship simulation stay on different update cadences. Share the code path; do not unify the frequency.
- Do not make `gdlint` mandatory. Do not add GUT or gdUnit4. Do not assert exact catalog counts.
- Do not pool projectiles on the strength of the Phase 6 measurements. LOD crossing dominated that cost.
- Do not wire n>5 routes or hyperdrive translation without a plan. Frozen setting files are `docs/setting/overview.md`, `corporations.md`, `planets.md`, and `date_time.md`. Do not edit them unless the request explicitly asks for a setting-doc edit.
- `SaveStore.save_dir` is injectable. Tests must keep using a project-local directory. Do not write the default `user://saves/` slots from the suite.

## What is already in good shape

Recorded so the audit is not relitigated as if the earlier refactors had not landed.

- Gameplay does not construct nodes. The only `Node` check under `scripts/gameplay/` is `WeaponHit` reading `session` and `catalog` off a shooter (A-6).
- `main.gd` is scene wiring. Flight, world, and menu work sit on `FlightLoopController`, `WorldController`, and `MenuController`.
- New habitat buildings go through `BuildingPanelRegistry` and `GameScreen`, not a `match` in `HabitatScreen`.
- Charter accept, pay, and cancel call `MissionSubsystem`. Market, dealer, yard, and fuel UI call `GameSession` or `ShipAssembly`.
- Ammunition, chassis, commodities, economies, fuels, modules, sectors, ships, and unspace have JSON Schema, generated `*Def` records, and CI checks. Sector completeness covers the 21-sector set. Stars, message emitters, and celebrity pilots are checked in `validate_catalog_refs.py` without generated record classes.
- File-level save round-trips exist. `tests/test_save.gd` points `SaveStore.save_dir` at a project-local directory.

The October 2026 audit inventoried all 82 gameplay scripts, all 100 presentation, UI, and dev scripts, and all 53 catalog JSON files. Files with no finding are not listed.

---

# 1. Design and content follow-ons

These were the whole of this file before the audit. The implemented behaviour is noted so it is not rebuilt. Only the remainder is open.

## D-1 Reactor fuel, traded fuel, and per-chemistry tanks

**Status:** Discuss. **Severity:** Medium.

Propulsion fuel is implemented. Reaction engines store typed fuel on `OwnedShip.fuels`. Each propulsion SKU has a built-in bunker (`fuel_capacity`) plus untyped `category: fuel` tank addons. Habitat prices live in `data/catalog/fuels.json` and roll per sector and GST day (`FuelEconomy`). Gravitic drives and integrated sails consume no propulsion fuel.

**Still open:** exchange-traded fuel commodities, per-chemistry tank SKUs, and reactor fuel for fission and fusion plants.

**Do not:** invent a second propulsion-fuel model beside `FuelEconomy`.

## D-2 Gravitic range and hyperdrive translation

**Status:** Discuss. **Severity:** Low.

Five gravitic SKUs are catalogued, including `hw_sundancer_loft` on the Flare-ON SK. Local field coupling is implemented: thrust scales with ambient gravity, and unspace gives only a weak fluctuating acceleration. Six `integrated_sail` workshop SKUs exist. No ship template defaults to a sail. Hyperdrive SKUs exist in `data/catalog/modules/hyperdrive.json` and are not a travel mode.

**Still open:** independent gravitic hyper-travel range, any gravitic-specific fuel rules, and ship hyperdrive translation. The last of those is also listed under [Not yet implemented](architecture.md#not-yet-implemented).

**Do not:** enable deeper unspace layouts or hyperdrive translation as a side effect of touching sails or gravitic thrust.

---

# 2. Stability and coupling

## A-1 Charter lifecycle is copied four times

**Status:** Discuss. **Severity:** High.

`MissionSubsystem` (`scripts/gameplay/mission_subsystem.gd`, about 1,400 lines, save version 5) owns passenger, freight, scan, and bounty charters as parallel offer maps, id counters, accept/cancel paths, dock resolution, and deadline failure. Offer generation itself is properly delegated to `PassengerCharters`, `FreightCharters`, `ScanCharters`, and `BountyCharters`. The lifecycle around those generators is not. `cancel_penalty` is the same formula in all four charter modules. Scan satisfaction is inlined on the subsystem; bounty satisfaction lives on `BountyCharters`.

The UI repeats the split. `passenger_charter_panel.gd`, `freight_charter_panel.gd`, and `scan_charter_panel.gd` each rebuild a tile grid, ship selector, and refresh cycle. Scan is embedded three ways: the peacekeeping registry entry, `CorporateOfficePanel` (current building), and `BarPanel` (A-2).

A fifth charter type, or a deadline-rule change, will be edited in the subsystem, four rule modules, and three panels.

**Direction:** One charter lifecycle helper (accept, cancel, late, resolve on dock, reputation and career logging) parameterised by kind. One charter board widget with kind-specific offer and accept hooks. Move scan satisfaction next to `ScanCharters`.

**Do not:** merge the four generators into one combinatorial module. Scan and bounty assembly rules are different on purpose. Do not rewrite charter balance while extracting the lifecycle.

## A-2 Bar scan desk ignores the building it was opened from

**Status:** Done. **Severity:** Medium.

`BarPanel.configure` stores the building and passes it to `ScanCharterPanel`. Scan and bounty boards list every habitat building of type `bar`, and the section visibility checks that building id. Davidson's remains the only bar in the catalog; a second bar gets its own desk.

## A-3 Mission harness writes offer maps directly

**Status:** Done. **Severity:** High.

The harness calls `MissionSubsystem.seed_harness_scan_offer` and `seed_harness_bounty_offer`. Those build one peacekeeping offer through `ScanCharters.build_pinned_offer` and `BountyCharters.build_pinned_offer` (same field assembly as the daily boards, with the chosen site, scan target, and bounty hull pinned) and replace today's board. Production rolls are unchanged. N on a harness grant stays 4.

**Do not:** treat the harness as production gameplay. Do not weaken production generation to match the harness.

## A-4 Mission reactions depend on a presentation subscription

**Status:** Discuss. **Severity:** Medium.

`GameSession.dock` publishes `SimEvent.docked` on `session.events`. `MissionSubsystem.on_event` runs only when `Simulation.dispatch_event` is called. Production does that in `MenuController._forward_session_event`. Headless tests subscribe themselves. `mission_harness.gd` does not. Any future caller that docks a session without that subscription will complete travel and silently skip charter resolution.

The bridge is documented in [architecture.md](architecture.md) and is not an accident. It is a load-bearing wire with one production owner.

**Direction:** Have `GameSession` notify the `Simulation` it was started with, or have `MissionSubsystem` subscribe to `session.events` when it is registered. Keep `MenuController` from being the only production forwarder.

**Do not:** delete `EventBus` or the coarse `changed` signal as part of this. UI still refreshes on `changed` (A-8).

## A-5 `GameSession` is again the behaviour hub

**Status:** Discuss. **Severity:** Medium.

Phase 2 split state into `PlayerState`, `WorldPresence`, `Fleet`, `Wallet`, and `CombatPersistence`. The facade grew back. `game_session.gd` is about 1,140 lines, with 36 forwarding properties, and it still implements travel, dock and undock, market buy and sell, ship purchase, salvage, combat repair, and career side effects.

`credits`'s setter writes `wallet.credits` and does not publish the credits event. `add_credits` and `try_spend_credits` do. Direct assignment is a footgun.

**Direction:** Stop adding feature methods here. New mutations belong on the slice that owns the state, with `GameSession` coordinating save and events. Decide explicitly whether the `credits` setter should publish or whether assignment should be removed from gameplay call sites.

**Do not:** add more forwarding properties. Do not change save JSON keys. Do not do another pure move of the same fields.

## A-6 `WeaponHit` pulls session and catalog off a Node

**Status:** Discuss. **Severity:** Medium.

`WeaponHit._shooter_session` and `_shooter_catalog` (`scripts/gameplay/weapon_hit.gd`) accept a hit only when the shooter `is Node` and then `get("session")` / `get("catalog")`. That is the one scene-tree dependency in gameplay. Projectiles, lasers, and proximity mines all arrive through it.

**Direction:** Pass a small `RefCounted` hit context (session, catalog, shooter id) from presentation into `WeaponHit.apply`.

**Do not:** move damage resolution into the projectile scripts.

## A-7 Typed catalog records are only half-adopted

**Status:** Discuss. **Severity:** Medium.

`ModuleDef`, `ChassisDef`, `ShipDef`, `SectorDef`, `CommodityDef`, `EconomyDef`, and `AmmunitionDef` exist, with both `get_*` dictionary getters and `get_*_def` typed getters on `Catalog`. Assembly, traffic spawn, translation nav, and several charter paths still use the dictionaries. `AssembledShip.chassis` is a `Dictionary` while installed modules are `ModuleDef`. `data_model.md` already calls the dictionary getters a remaining pass. A mistyped key still returns a default and stays green.

**Direction:** Move gameplay readers that already have a `*Def` onto `get_*_def`, starting with `ShipAssembler` / `ShipAssembly` and `AssembledShip.chassis`. Leave presentation on dictionaries until that pass is done, which is what `data_model.md` already describes.

**Do not:** delete the dictionary getters in the same change as the first caller migration. UI still uses them.

## A-8 Docked UI rebuilds on every `session.changed`

**Status:** Discuss. **Severity:** Medium.

`GameScreen.bind` connects `session.changed` to `refresh` and never disconnects it (`scripts/ui/game_screen.gd`). Habitat, market, dealer, yard, and charter panels clear and rebuild on that signal. `changed` also fires for logs, ammo selection, and sensor toggles. `TerminalPanel` already has a softer docking-bay refresh. The yard and the charter boards do not.

`HabitatScreen` detects the shipyard by `script` path ending in `shipyard_screen.gd` rather than by type.

`hud.gd` (about 640 lines) rebuilds weapon chits from `_process`. Worth measuring before treating it as a defect. `shipyard_screen.gd` (about 780 lines) is the largest docked panel and refreshes in full.

**Direction:** Disconnect `changed` in `_exit_tree`. Split "log line" from "board data changed", or follow the terminal's soft refresh where the board is unchanged. Identify the shipyard with `is ShipyardScreen` or a registry flag.

**Do not:** delete `changed` until subscribers have a narrower signal (see the Phase 1 event-bus note in the archive).

## A-9 Player ship node records career shots and warning logs

**Status:** Discuss. **Severity:** Medium.

`player_ship.gd` writes `session.last_log` for fuel and power warnings and calls `session.career.record_shots` when weapons fire. It also reaches the parent for `try_interact` and the world. `npc_ship.gd` walks its parent chain for the world root. Rules and career counters then depend on the scene tree.

**Direction:** Return warning and shot results from the sim step `ShipSimCore` already runs, and let the session record them. Inject the interact callable from `main.gd` when the ship is configured.

**Do not:** fold the player back onto the NPC tick rate.

## A-10 Ballistic projectiles duplicate sweep and hit application

**Status:** Discuss. **Severity:** Medium.

`mass_driver_round.gd` and `rocket_projectile.gd` each implement sweep, shooter attribution, and `WeaponHit.apply`. `laser_beam.gd` is a different weapon and should stay separate. `proximity_mine.gd` applies packets on overlap, which matches the other weapons. `point_defence_pellet.gd` is cosmetic.

**Direction:** One shared sweep-and-apply helper used by the mass driver and the rocket. Mines can call the same apply path when A-6 lands.

**Do not:** pool projectiles. Phase 6 measured that cost below LOD crossing.

## A-11 `WorldLoader` owns layout, nav, traffic geometry, and volatile sites

**Status:** Discuss. **Severity:** Medium.

`scripts/presentation/world_loader.gd` is about 1,260 lines. It spawns sector and unspace scenes, caches nav contacts, and builds the arrival geometry `traffic_routing.gd` consumes. `nspace_field.gd` is about 790 lines of the same shape for unspace presentation.

**Direction:** Split spawn from the nav and traffic adapter, keeping the public methods `WorldController` and gameplay already call. Touch unspace only when that code is already being edited.

**Do not:** add world kinds. Moons and belts stay ordinary sectors (Phase 4).

---

# 3. Content authoring

## A-12 Several catalogs have no schema check

**Status:** Done. **Severity:** High.

`fuels.schema.json` is a generator input, so CI validates `fuels.json` and `Catalog` loads `FuelDef`. `validate_catalog_refs.py` checks fuel price ranges and module `fuel_type` ids, star records, message-emitter ids, channels, tones, and placeholders, and unique celebrity pilot ids and names.

**Do not:** generate `*Def` classes for every small table in one pass. Fuels are the one that already has a schema.

## A-13 A new sector still needs a hand-maintained tail

**Status:** Done. **Severity:** High.

`generate_sector_bundle.py` writes the `corporate_presence.json` row from `presence_anchors`, and emits the peacekeeping desk plus liaison offices when `peacekeeping` is set. `ScanCharters` treats a civic habitat that lists `{sector_id}_peaceforce` as a scan habitat, so the old hardcoded habitat table is gone. Headquarters stay in `sync_corporate_hqs.py`. The tail is documented under "Adding a sector" in `data_model.md`.

**Do not:** invent new world types for moons or belts.

## A-14 Module and habitat rules are duplicated and brittle

**Status:** Discuss. **Severity:** Medium.

Maker allow-lists, life-support flags, cargo floors, and retired module ids are enforced both in `scripts/tools/validate_catalog_refs.py` and in `tests/test_catalog.gd`. A new manufacturer fails CI until both are edited. `test_catalog.gd` also requires exactly one shipyard per civic habitat (with an exception list), exactly one public route for named belt and hub sectors, and one terminal plus one HQ on stations. `test_catalog.gd` and `test_translation.gd` pin the Proxima–Bela n=4 solution at 42.

Floors (`_check_min_count`, validator SKU floors) are the right shape and should stay.

**Direction:** One rule module or data file for maker and retired-id checks. Prefer "maker exists on `corporations.json`" over a handwritten allow-list where the setting allows it. Keep the solution-42 check only if that edge is a designed constant. Soften layout checks that are really "the current map looks like this".

**Do not:** go back to exact SKU counts.

---

# 4. Test gaps

## A-15 High-risk gameplay with no direct test

**Status:** Discuss. **Severity:** Medium.

Most gameplay modules have a suite. These do not:

| Module | Why it matters |
|--------|----------------|
| `cargo_requirements.gd` | Charter accept depends on it |
| `combat_persistence.gd` | Hull, integrity, and shield charges across save and dock repair |
| `traffic_detection.gd` | Staggered detection. `traffic_director.gd` tests cover caps and setup, not this |
| `commodity_message_emitter.gd` | Sibling emitters are tested; this one is not |
| `pool_message_emitter.gd` | Base class for the ticker pools |

`game_version.gd` is a constant. A test would not earn its keep.

Save file IO is covered via `SaveStore.save_dir`. That closed the Phase 0 gap. Do not reopen it.

**Direction:** Headless cases for cargo rejection, combat-state round-trip, and one detection stagger step. Emitter tests can follow `test_message_emitters.gd`.

**Do not:** boot the scene tree to test these. Do not add GUT.

## A-16 Dev flight sandboxes copy the production tick

**Status:** Discuss. **Severity:** Low.

`FlightSandboxBase` rebuilds HUD nav that `FlightLoopController` already updates. `combat_sandbox.gd` ticks `TrafficActor` and detection itself instead of going through `TrafficDirector`. `ship_assembly_sandbox.gd` hosts the real yard and is fine. `system_render_tester.gd` and `smoke_scenes.gd` use `WorldLoader`.

**Direction:** When those sandboxes are next edited, call the production flight tick with the sandbox session. Not worth a dedicated change on its own.

**Do not:** make sandboxes depend on the full habitat UI.

---

# 5. Documentation drift

Design docs may be edited when an item below is picked up. The frozen setting files (`overview.md`, `corporations.md`, `planets.md`, `date_time.md`) may not.

## A-17 Design docs that will send the next change to the wrong place

**Status:** Done. **Severity:** High.

Corrected `data_model.md` (hull damage, sensor contacts, `hull_color`, module paths and categories, `integrated_sail`, catalog file table, mission save version 5, implemented-subset table), `architecture.md` (gameplay directory, volatile grants, n=5/n=6 translations versus a single n=4 layout, `route_friction_delta`, life-support path, sector count), `README.md` (project-status section and charter list), `sprite_sizes.md` (portraits 120×160), `docs/README.md` (corporation index, no hardcoded count), and `commodity_economy.md` (typed trade events are implemented). The setting-index leftovers were closed with A-18.

Verified against the tree on 22 October 2026.

| Document | Claim | Code or catalog |
|----------|--------|-----------------|
| `data_model.md` NPC traffic | "player hull remains invulnerable this slice" | `GameSession.apply_combat_hit`; docking repairs hull. `architecture.md` already says shots apply damage |
| `data_model.md` NPC traffic | "Unlabelled NPC blips" across the sector | Undetected NPCs are hidden. `architecture.md` sensor section |
| `data_model.md` chassis `hull_color` | "HTML colour for sprite modulate" | Hull sprites render at `Color.WHITE`. `hull_color` is identity metadata (`architecture.md`, `sprite_sizes.md`) |
| `data_model.md` How to extend | "Add entry to `modules.json`" | Modules are `data/catalog/modules/<category>.json` |
| `data_model.md` implemented-subset table | Shields, ECM, and player hull damage are still the setting target. Weapons row is "light laser and mass driver" | Shields, point defence, and player hull damage are in the combat path |
| `data_model.md` catalog table | Omits `backgrounds.json`, `fuels.json`, `scan_missions.json`, `bounty_missions.json`, `volatile_sites.json`, `sanctions.json`, `stars.json` | All of those files are loaded by `Catalog` |
| `architecture.md` volatile translations | Opens "Missions (future) can grant…" | `VolatileTranslation`, `volatile_sites.json`, and charter grants are implemented. The rest of that section describes the real system |
| `architecture.md` Not yet implemented | "Unknown/private Unspace routes" and "Deeper N-space routes (n > 4)" | Volatile grants are private non-catalog routes. `routes.json` has 38 edges, all with an n=4 translation, plus 7 n=5 and 2 n=6 translations. `unspaces.json` is still only `n4_default` |
| `architecture.md` economic events | `route_friction_delta` described as UI | Field exists on session and in `CommodityEconomy`. No UI under `scripts/ui/` |
| `architecture.md` shipyard paragraph | Life-support flags "in `modules.json`" | `data/catalog/modules/life_support.json` |
| `architecture.md` directory table | Gameplay row stops at the Phase 2 types | Missions, messages, charters, fuel, sanctions, autopilot, target scan, and volatile translation are missing |
| `README.md` line 7 | Links to `#project-status` | That heading does not exist |
| `sprite_sizes.md` | Quick-reference portraits are 1024×1024 | The UI-art section of the same file, and the README, say 120×160 |
| `docs/README.md` and `setting/README.md` index | "Sixteen megacorporations" | `corporations.md` has 43 corporation sections, matching 43 ids in `corporations.json`. The index line is stale. The body of the setting doc is not |
| `commodity_economy.md` | Typed `CommodityTraded` events listed as future work | `SimEvent` and `MissionSubsystem` already consume them |

**Direction:** One doc pass over `data_model.md`, the "Not yet implemented" list, and the index tables. Say clearly that higher-order translations exist and that a separate 5-space or 6-space layout does not. Fix the README anchor by adding the section or removing the link.

**Do not:** edit `docs/setting/` as part of this item. That is A-18. Do not treat volatile sites as permission to add public n>5 routes.

## A-18 Setting docs that disagree with the catalog

**Status:** Done. **Severity:** Medium.

The stale status lines were in files that are playable rules, not lore. Those files now live under `docs/design/content/`, and the claims were corrected there: charter status includes freight, scan, and bounty; the public graph is 38 edges; volatile grants are private translations and are not economy edges. Reputation and sanction rules moved from `overview.md` into `missions.md`. GST clock behaviour moved from `date_time.md` into `gst.md`. The setting index no longer carries an implementation table or a corporation count. Frozen files are `overview.md`, `corporations.md`, `planets.md`, and `date_time.md`.

---

# 6. Explicitly out of this audit

- On-foot play, named NPC dialogue, and a combat game-over screen. Already listed as not implemented. No new evidence.
- A C# port, projectile pooling, unified player/NPC tick rate, and mandatory lint. Standing decisions above.
- Rewriting `CombatPilot` or traffic AI. They are large because the behaviour is large, and they are among the best-tested systems. Split them only along a seam that a concrete bug is already crossing.
