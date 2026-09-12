# Architecture

High-level structure of the Godot 4.7 near-orbit game. Historical design notes from the original Java/XML design repo are reference only.

## Design principles

1. **Gameplay logic without nodes** — rules, state, and catalog loading live in `scripts/gameplay/` as `RefCounted` types. No scene tree dependency.
2. **Presentation adapts data** — `scripts/presentation/` wires Godot nodes to gameplay objects (`CharacterBody2D`, world scenes, camera).
3. **UI is thin** — `scripts/ui/` binds `CanvasLayer` overlays to session and catalog; it emits signals rather than mutating game state directly.
4. **Data-driven content** — orbit layouts, interactables, ships, habitats, and jump routes come from JSON under `data/catalog/`.

## Directory layout

| Path | Role |
|------|------|
| `scripts/gameplay/` | `Catalog`, `GameSession`, `PlayerState`, `WorldPresence`, `Fleet`, `Wallet`, `CombatPersistence`, `EventBus`, `SimEvent`, `GameVersion`, `SaveStore`, `GalacticCalendar`, `Simulation`, `SimClock`, `SimSubsystem`, `EconomySubsystem`, `MissionSubsystem`, `GameClock`, `CommodityEconomy`, `ShipAssembler`, `ShipAssembly`, `ShipSimCore`, `ShipOperations`, `ShipWeapons`, `ShipCombat`, `ShipCombatState`, `ShipMotion`, `ShipStats`, `OwnedShip`, `AssembledShip`, `ShipOperatingState`, `SensorSystem`, `WeaponHit`, `TransponderBroadcast`, `CombatPilot`, `TrafficDirector`, `TrafficActor`, `InteractableDef` |
| `scripts/presentation/` | `main.gd`, `FlightLoopController`, `WorldController`, `MenuController`, `player_ship.gd`, `npc_ship.gd`, `traffic_view.gd`, `world_loader.gd`, `world_object.gd`, `interactable.gd`, camera, starfield |
| `scripts/ui/` | HUD, main menu, save overlay, pause overlay, jump overlay, `UiRoot`, `ScreenStack`, habitat/shipyard screens |
| `scenes/ui/` | Full-screen habitat UI, shipyard assembly, reusable components |
| `data/catalog/` | JSON catalogs (schemas: [data_model.md](data_model.md)) |
| `assets/` | Art referenced by catalog paths |
| `themes/` | `cartel_theme.tres` — corporate UI theme (see [ui_theme.md](ui_theme.md)) |

## Data flow

```mermaid
flowchart LR
  JSON[data/catalog JSON] --> Catalog
  Catalog --> Session[GameSession]
  Catalog --> Assembler[ShipAssembler]
  Catalog --> Loader[WorldLoader]
  Session --> HUD
  Session --> UiRoot[UiRoot + ScreenStack]
  Session --> Jump[JumpOverlay]
  Session --> Assembly[ShipAssembly]
  Catalog --> Assembly
  UiRoot --> Habitat[HabitatScreen]
  Habitat --> Shipyard[ShipyardScreen embedded]
  SaveStore --> UserSaves[user://saves/slot_N.json]
  Loader --> World["$World nodes"]
  Assembler --> PlayerShip[PlayerShip configure]
```

`GameSession` is an aggregate root: `PlayerState`, `WorldPresence`, `Fleet`, `Wallet`, and `CombatPersistence` own the fields; public properties on `GameSession` forward to those slices so UI and tests keep using `session.credits` and `session.owned_ships`. Save JSON keys are unchanged — `to_dict` / `from_save` compose the slice serializers.

On startup, `main.gd` wires three presentation controllers and delegates to them:

1. Loads `Catalog.load_default()`.
2. **MenuController** shows the **main menu** (New Game / Load / Exit).
3. **New Game** — player enters callsign, portrait, and background; `GameSession.start_new_game` seeds fleet from `backgrounds.json`, docks at the kit's habitat, and opens **HabitatScreen** at the Terminal.
4. **Load** — reads a JSON slot from `user://saves/` and restores session, fleet, cargo, spare parts, and flight state.
5. **WorldController** assembles the current ship via `ShipAssembler.assemble_owned` and calls `WorldLoader.load_sector` or `load_unspace` to populate `$World`.
6. **FlightLoopController** ticks traffic and feeds nav/signature HUD each physics frame when flight is active.
7. Controllers bind HUD and overlays to session state; `main.gd` keeps `session` and `try_interact` on the node for parent duck-typing.

## Habitat UI (menu planet)

Docking opens **UiRoot** — a full-screen opaque Control UI (not a dim overlay). Navigation uses **ScreenStack** (`push_screen`, `pop_screen`, `replace_screen`):

- **HabitatScreen** — building list from catalog with `short_desc` tooltips on each row; building header row (33% name + long description left-aligned, 66% location art right-aligned, scaled for future art assets); type-based content below (terminal, Exchange market, embedded Shipyard assembly). Building `short_desc` is no longer shown in the action log on visit — only transactional messages appear in the log footer.
- **Terminal** — full-height three-column layout: docked ship list, ship detail (modules/stats), and admin column (rename ship, launch status from `ShipAssembly.undock_blockers`, Launch button when cleared).
- **ShipyardScreen** — embedded in the habitat content pane when Shipyard is selected: docked ships, slot board with drag-and-drop fitting, tabbed yard stock by module category, buy/sell/refuel. Propulsion stock sorts by price, type, or thrust; row meta shows `engine_type` and thrust. Power stock sorts by price, type, or MW; row meta shows `plant_type` and output. Computer stock sorts by price, type, or CU; row meta shows `core_type` and capacity. Life support stock sorts by price or crew; row meta shows crew, Transport vs Habitat, and luxury flags. Hover any yard part or occupied slot for full module specs via `ModuleSpecText.format_tooltip()`. Propulsion modules carry `brand` and `engine_type` (`chemical` | `hydro_thermal` | `electric_plasma` | `direct_fusion` | `antimatter` | `gravitic`); power modules carry `brand` and `plant_type` (`fission` | `fusion` | `radioisotope`); computer modules carry `brand` and `core_type` (`silicon` | `photon` | `quantum`); life support modules carry `brand` and optional `ls_habitat` / `ls_comfort` / `ls_luxury` capability flags in `modules.json`. `ls_habitat` marks live-aboard cabin volume; its absence is transport seating. LSS `volume` includes that cabin.

Reusable DnD components live under `scenes/ui/components/` (`module_slot`, `module_stock_item`).

UI scripts receive a **UiContext** (`catalog`, `session`, `stack`, callbacks). They never load JSON or run gameplay rules directly — they call `GameSession` / `ShipAssembly` and refresh on `session.changed`.

Location and building art paths live in catalog JSON under `assets/ui/locations/` (placeholder SVGs today).

### Ship assembly sandbox

For fitting and engineering work without the full game loop, run `scenes/dev/ship_assembly_sandbox.tscn` (CLI `--scene` or editor **F6**). It bootstraps `Catalog`, a sandbox `GameSession` (`session.sandbox = true`), and embeds `ShipyardScreen` with buy/sell disabled and unlimited module drag from catalog. Toolbar actions add empty hulls, strip modules, and restore manufacturer templates. Fitting validation (mounts, mass, volume) matches the main game.

### Combat sandbox

For 1v1 combat iteration without the full game loop, run `scenes/dev/combat_sandbox.tscn` (CLI `--scene` or editor **F6**). The setup overlay lists all manufacturer templates from `ships.json` with read-only stats and installed systems. **Begin bout** places player and opponent on the starfield just beyond combined weapon range, facing each other with zero velocity. Opponent attitude is **Fight to the death** (default, stays engaged) or **Standard NPC** (provoked fight-or-flight from `TrafficActor`). **Esc** ends the bout and returns to setup. Uses production `PlayerShip`, `NpcShip`, `ShipCombat`, and HUD; no world landmarks or traffic director.

### Stealth sandbox

For signature and detection iteration without Proxima traffic, run `scenes/dev/stealth_sandbox.tscn` (CLI `--scene` or editor **F6**). **Begin drill** spawns the player at the origin with transponders off and 1–12 copies of the chosen target hull scattered near the rim of the player’s **`sensor_range`** (minimap matches that envelope). NPC sprites and radar blips stay hidden until channel threshold detection (`player_detected`). NPCs remain peaceful until sandbox acquire logic sees the player via signature channels or visual range, then they **ENGAGE** or **FLEE** per attitude. **Esc** returns to setup. Does not change production traffic’s combat-only reciprocal sensing cull.

## Main scene structure

`scenes/main.tscn`:

- **Starfield** — parallax background bound to follow camera.
- **World** — empty at edit time; populated at runtime by `WorldLoader`.
- **PlayerShip** — inertial flight, interaction sensor, camera.
- **HUD** — capability-gated flight chrome: basic instrument cluster (computer) including a **signature panel** (thermal / gravitational / EM / computational totals, transponder on/off, active sensors on/off), local radar and waypoint arrows (sensor), transponder label overlay (`sensor_read_beacons`). Hidden when docked.
- **MainMenu** — New Game, Load, Exit.
- **NewGameOverlay** — callsign, portrait picker, and background kit form.
- **SaveOverlay** — three-slot save/load browser.
- **PauseOverlay** — Resume, Save, Load, Quit to Menu (Escape during flight).
- **UiRoot** — opaque full-screen habitat UI with ScreenStack.
- **JumpOverlay** — Unspace route list at jump gates.

## Player loops

### Orbital flight

- `ShipSimCore` orchestrates the shared flight rules (shields, ops, signature glow, mass/stats, weapons, motion). The player calls every step each physics frame for HUD telemetry; slotted NPC traffic uses the same steps with interval stats refresh; unslotted NPCs skip ops/weapons/stats and only run cheap motion + glow.
- `ShipMotion` integrates thrust, rotation, boost, and damping from `ShipStats` (derived from assembled modules and loaded mass), modulated by operating-state `thrust_factor`.
- Hold **Space** or **LMB** (`fire`) to discharge installed weapons along ship facing. `ShipWeapons` handles rate-of-fire cooldowns and ammo; `ShipOperations` allocates weapon power only while firing.
- `play_bounds` per sector defines the distant dust ring (visual landmark only; player flight is unbounded).
- `Interactable` areas on world objects; player `InteractSensor` picks nearest valid target.
- Flight HUD elements require installed module capabilities (`basic_hud`, `local_sensor`, `local_system_waypoints`, `sensor_read_beacons`, `4_space_topology` for unspace exit labelling). In-system ships require a powered `vessel_registration_beacon` (Commercial Article 19).

### Interaction kinds

| Kind | Behaviour |
|------|-----------|
| `inspect` | Log flavour text; track `inspected_ids` |
| `salvage` | One-time credits; id tracked in `salvaged_ids`; wreck visual modulated |
| `dock` | Pause tree, hide HUD, open UiRoot habitat screen, park current ship at habitat |
| `translate` | Pause tree, open jump overlay with sector `mappings` (pick destination + N-space depth) |
| `arrive` | At 4-space exit portal: complete transit into destination 3-space orbit |

Dock and jump-route selection set `get_tree().paused = true` until the overlay closes. **4-space transit itself is unpaused** — same inertial flight with hazards.

### Docking and shipyard

1. `[E]` at habitat → `session.dock(catalog, habitat_id)` → **HabitatScreen**.
2. Visit buildings from catalog list; **Proxima Exchange** for commodity buy/sell (per-ship cargo holds); **Shipyard** shows assembly inline in the habitat content pane.
3. Chassis is **fixed** per ship; modules install from **spare_parts** inventory by dragging stock onto compatible slots (or click spare then click slot). Buy at yard fills spares; drag off a slot to uninstall. Engineering panel shows mass, volume, power, compute, heat, fuel budgets.
4. Undock: **Terminal** → select docked ship → **Undock** → resume flight.

Ships parked at a habitat **stay there when jumping sectors** (only the aboard ship travels).

### Galactic Standard Time (GST)

Session state stores `gst_seconds` (see [setting/date_time.md](../setting/date_time.md)). `GalacticCalendar` formats timestamps. `Simulation.step` in `main.gd` advances time each frame (GST freeze from **MenuController** when paused, in menus, or docked in habitat UI) and dispatches registered subsystems (economy reposts market quotes on day rollover). `GameClock` remains a thin facade over `Simulation` for tests and legacy callers.

Successful gameplay mutations publish typed events on `GameSession.events` (`EventBus` + `SimEvent` factories — e.g. `commodity_traded`, `sector_entered`, `docked`). **MenuController** forwards those events to `Simulation.dispatch_event(session, catalog, evt)`, which calls `SimSubsystem.on_event(session, catalog, evt)`. UI still refreshes on the coarse `session.changed` signal; typed events are for simulation subsystems and future mission/faction hooks, not HUD wiring.

`MissionSubsystem` is a spike (not a content system): one hardcoded Proxima→Bela food delivery auto-accepted on new game, tracked via commodity and sector events, paid on completion, persisted under `subsystems.missions`.

| Context | GST behaviour |
|---------|---------------|
| Realspace flight | 1:1 with real time |
| Habitat / building UI | 1:1 (tree may be paused; clock uses `PROCESS_MODE_ALWAYS`) |
| Unspace flight | Irregular pulses — stutter and jumps, more erratic at higher N |
| Jump gate entry / exit portal | Discrete lump from sector `mappings[]` (`entry_seconds`, `exit_seconds`, `time_jitter`) |
| Main menu, pause, save/load, jump picker | Frozen |

HUD and **HabitatScreen** header show `GstClockLabel` at seconds resolution. `session.changed` is **not** emitted every second — widgets poll `gst_seconds` directly.

### Jump travel (3-space ↔ 4-space ↔ 3-space)

1. `[E]` at jump gate (3-space only) → jump overlay lists destinations from `mappings[]`.
2. Select destination → confirm **4-space (n=4)** route. Known `solution` integer shown as flavour; no typing yet.
3. Confirm → `session.enter_unspace` → entry translation lump applied → `WorldLoader.load_unspace` → player at 4-space entry spawn, dim starfield behind undulating geometry.
4. Fly through 4-space: an **irregular Delaunay topographic mesh** (Poisson-scattered vertices, random per-vertex height) fills the play disk under the ship as a static ground plane in 3D. Player perturbations (edge kicks, ripples, radial bound) are disabled for now. GST advances irregularly while in transit.
5. `[E]` at **Exit Portal** (3D disc on a fixed host face; hidden 2D interactable for input; labelled only with `4_space_topology` sensors) → exit translation lump applied → `session.arrive_from_unspace` → load destination sector orbit.

Hyperdrive-equipped ships may later translate without a gate or from other 4-space regions — not implemented.

```mermaid
flowchart TD
  Orbit3[3-space orbit] -->|E Jump gate| Overlay[Pick dest plus 4-space]
  Overlay -->|Confirm| Four[Flyable 4-space]
  Overlay -->|Cancel| Orbit3
  Four -->|E Exit portal| Dest3[Destination 3-space orbit]
```

## World loading

3-space sectors (`proxima`, `bela`, and the nine additional worlds in `sectors.json`) use a structured layout in `worlds.json`:

- **`planet`** — lit 3D globe rendered in an isolated `SubViewport` and composited as a 2D disc at the origin (`PlanetBackdrop`, diameter 2000, `z_index -50`). Slow axial spin with a sun-lit day/night terminator; optional catalog `albedo` / `night_lights` wrap maps (legacy `sprite` is ignored for the globe mesh).
- **`orbital_ring`** — evenly spaced orbitals on a rotating ring (`OrbitalRing`); habitat is the largest and dockable; unnamed orbitals are visual-only
- **`jump_gate`** — static gate farther out (angle derived from sector id)

4-space layouts are defined in `unspaces.json` as a **`field`** block: a one-shot Poisson-scattered point field, Delaunay triangulation (with optional convex quad merges), independent random vertex heights, and a fixed exit portal on a chosen host face. Legacy flat `entities` lists in `worlds.json` are no longer used for unspace loading.

`WorldLoader.load_unspace` spawns an `NspaceField` instead of sector entity scenes. No dust ring in unspace. The field builds the mesh once from catalog tuning (`fov_vertex_count`, `scatter_margin`, `quad_merge_chance`, `height_scale`) so the play zone plus an FOV margin stays off-screen. **3D presentation** is rendered in an isolated `SubViewport` (`own_world_3d`) and composited behind the ship via `_draw()` on the field node. Heights map to the view axis (`Z`) as a ground plane under the 2D ship; an orthographic `Camera3D` tracks the active `Camera2D`. The exit portal is placed once on a host face from the route seed; its visual is a 3D disc in the backdrop while a hidden 2D `Area2D` handles `[E]` interaction. Unspace applies no field forces on the player; ship flight uses the same `ShipMotion` path as 3-space orbit. **Ascidians** (1–3 per visit, visit-randomised spawn) wander in 2D logic but draw in 3D at mid height between min and max vertex Z; opaque terrain depth-tests against them so peaks occlude naturally. They appear as faint unlabeled radar contacts. Higher-N spaces may later project 3D geometry into the play plane; 4-space does not.

`WorldLoader` maps 3-space entity `kind` to packed scenes:

| Kind | Scene |
|------|-------|
| `habitat` | `scenes/world/habitat.tscn` |
| `jump_gate` | `scenes/world/jump_gate.tscn` |
| `orbital` | `scenes/world/orbital.tscn` (visual-only station) |
| `beacon` | `scenes/world/beacon.tscn` |
| `wreck` | `scenes/world/wreck.tscn` |
| `debris` | `scenes/world/debris_rock.tscn` |
| `hazard` | `scenes/world/hazard.tscn` (legacy; not used in 4-space) |
| `planet_limb` | Sprite2D spawned in code (legacy) |

Habitat and jump gate have interactable areas but **no solid collision** — the player flies over them. Orbital ring phase is persisted in `GameSession.orbital_phase_by_sector` (saved/loaded).

Each configured world object uses `WorldObject.configure(entity, catalog, session)` for position, label, sprite override, and interactable binding. 4-space uses `NspaceField.configure(unspace, catalog, session, play_bounds)`.

`WorldLoader.load_unspace` reads the `field` block from `unspaces.json` (palette, scatter/Delaunay topo, portal, inhabitants). `GameSession.unspace_solution` is set in `enter_unspace` from the selected route mapping and persisted across saves. Local radar in unspace scales to `play_bounds`. Exit portal nav contacts require the **`4_space_topology`** sensor capability.

The dust ring is a `Line2D` octagon generated from `play_bounds` at 3-space sector load time (not used in unspace). Local radar in 3-space scales to **content radius** (`max(jump_gate_radius, orbital_ring_radius) × 1.15`) so contacts stay readable when the dust ring is much larger than the playable landmarks.

## In-system NPC traffic (3-space)

`TrafficDirector` (gameplay) owns spawn policy, fleet size, sim slots, detection stagger, and actor AI when a sector loads. `TrafficView` (presentation) owns the `Traffic` node tree — `npc_ship.tscn` instances for slotted actors and far sprites for the rest. **FlightLoopController** ticks the director then syncs the view each physics frame. Not active in Unspace or while docked.

- **Density** — log-scaled from `population_billions` on the sector (`traffic.json` caps; Proxima ~100 ships at population max, smaller worlds less).
- **Spawn** — on sector arrival, trip roles appear 15–85% along their corridor toward destination; loiter/runabout scatter near the jump gate and orbitals. Cycle replacements still launch from origin waypoints.
- **Variation** — per-ship cruise jitter; trip routes steer directly to destination with optional lateral offset at arrival spawn.
- **Simulation LOD** — up to `sim_slot_max` (~20) nearest ships run full `ShipSimCore` steps (`ShipOperations`, weapons, interval stats) and `NpcShip` physics. The rest of the fleet (~100 cap) are kinematic sprites with cheap cruise AI and motion-only sim.
- **Presentation LOD** — follows sim slots: slotted ships use `NpcShip` (`CharacterBody2D`); unslotted ships are distant sprites regardless of distance inside `near_lod_radius`.
- **Roles** — transit, shuttle, dock_cycle share one-shot waypoint trips; loiter circles near the jump gate; runabout wanders between named anchors (habitat, gate, orbitals) and random free points inside the traffic envelope, repicking on arrival and optionally despawning at anchor stops (50% coin flip).
- **Lifecycle** — trip roles despawn on arrival at habitat, gate, or orbital interactable radius; runabouts may despawn at anchor stops or pick a new waypoint; director immediately spawns a fresh ship at a newly chosen origin (not the previous destination). FLEE ends after a timeout or when the player is far away (returns to TRAFFIC), or cycles out on reaching the flee anchor (habitat/gate); fleeing ships use peaceful velocity blending so they turn tightly instead of settling into orbit.
- **Combat** — provoked only; NPCs engage or flee at full engine cruise. ENGAGE sim-slotted NPCs use an instance `CombatPilot` (`scripts/gameplay/combat_pilot.gd`) fed a kinematic snapshot (position, velocity, facing, thrusting, weapon profile, max speed). Three range bands: **approach** (`> 2× weapon range`) closes at full speed when the target recedes or half speed when both close; **setup** (`weapon range` to `2× range`) flies a ±45° pass at ~55% speed; **dogfight** (`≤ weapon range`) energy-turns on intercept aim, coasts while lining up a shot, and fires whenever a feasible shot exists. When range opens toward `R`, a **maneuver interrupt** pauses fire and burns to cancel sideways relative velocity before closing; orbiting at constant range is treated the same way with **orbit latch hysteresis** so brief radial taps do not drop MANEUVER. Combat steering holds full `rotation_speed` until heading error is tiny. Per-bout standoff and closing-style jitter on `reset()`. **Pilot skill** (`NOVICE` / `EXPERIENCED` / `ELITE`, rolled on `reset()`) sets velocity EMA smoothing, fire graze radius, orbit-exit thresholds, and whether a thrusting target's **facing feint** is believed for intercept/receding/orbit (sticky for the burn). Intercept uses smoothed `target_vel` from `motion.velocity`, not `CharacterBody2D.velocity`. Ballistic, plasma, and rocket rounds inherit shooter velocity at spawn; intercept aim matches that model. Player/NPC hull collision is the **convex hull of chassis SVG primitives** via `HullHitbox` (not texture bounds); scene capsules remain fallback until configure/bind. Fire is independent of band; bore-sight on the aim point unless `CombatPilot.GUIDED_OFFBORE_FIRE` is enabled (future homing). `ShipCombat` resolves typed damage packets (PD → shields → armour → Hits/Power/Compute). Player and NPC shots apply combat damage; at 0 Hits thrust and weapons cut off. Docking repairs hull and integrity.
- **Sensors** — Branded sensor SKUs carry product-level `sensor_range`, `sensor_sensitivity`, optional `sensor_sensitivity_passive`, and `has_active` (no `detectors[]` in JSON). `SensorSystem` caches max range and per-channel sensitivity (active vs quiet profiles) at assemble time; in flight the player toggles **Active sensors** (`R`, `OwnedShip.active_sensors_enabled`) to choose full vs quiet sensitivity and whether active packages add ping **`signature{}`**. **Live signature** gates other contributions by operating state (thrust, fire, transponder, power load, compute use) with short propulsion/weapon afterglow. Detection and the flight HUD read live values; shipyard shows fitted totals. **`sensor_range`** is the hard envelope; inside it, contacts appear via **visual** (`visual_contact_radius`, 250 m default), **transponder override** (broadcasting + `local_sensor`), or **channel threshold** (`signature × sensitivity × range_weight ≥ threshold`, easier close / harder at rim). Undetected NPCs are hidden (no sprite, no radar blip). Landmarks/orbitals stay on the nav-contact path. Beacon text overlay only for detected, broadcasting ships with `sensor_read_beacons`. NPC traffic treats active sensors as on. NPC combat steering uses live player position only when the NPC has a reciprocal contact. Map rim aligns with content radius, not the dust ring.
- **Cruise** — peaceful traffic capped at `cruise_speed_fraction` (default 33%) of each hull's assembled `max_speed`; engage/flee uses full engine rating.
- **Bounds** — NPC recycle envelope is `gate_radius × 1.25`; player flight has no position clamp.

Catalog: `data/catalog/traffic.json`. Presentation: `TrafficView`, `scenes/npc_ship.tscn`, `scripts/presentation/npc_ship.gd`.

## Graphics convention

| Format | Use |
|--------|-----|
| **SVG** | Ships, stations, gates, beacons, wrecks, debris, orbitals |
| **PNG** | Starfield tiles, planet disc, painterly backgrounds |

Chassis entries reference hull **sprites**; SVG paint is the source of color (hull sprites render at `Color.WHITE`). The optional `hull_color` field is identity metadata (e.g. future radar/livery), not a sprite tint. World entities may override `sprite` and `modulate` in JSON. Workshop chassis swaps update both stats and hull appearance immediately.

**Production dimensions:** [sprite_sizes.md](sprite_sizes.md) — author-at canvas sizes so 1 SVG pixel = 1 world unit (no import-scale compensation).

Regenerate placeholders: `python3 scripts/tools/generate_placeholder_art.py` (runs Godot import for new SVG/PNG sidecars). Do not run on authored hull SVGs without guarding files — see sprite size catalog. If import is skipped, run `godot --path . --import --headless --quit` manually.

UI styling uses the shared **Cartel corporate theme** — see [docs/design/ui_theme.md](docs/design/ui_theme.md). Reference viewport: **1920×1080**.

## Save / load

- Three fixed slots: `user://saves/slot_1.json` … `slot_3.json` (directory configurable via `SaveStore.save_dir` for tests).
- Saves store pilot identity, full `GameSession` state (including `spare_parts`), owned ship instances (modules, per-ship cargo, fuel, ammunition), player flight position/velocity/facing, and `game_version` (from `GameVersion.VERSION`).
- Optional top-level `subsystems` envelope: `Simulation.collect_save()` writes one versioned section per registered `SimSubsystem` (`{version, data}` keyed by subsystem `id`). `Simulation.apply_save()` restores each section (running `migrate` when the stored version is older). Missing envelope on v1/v2 saves is valid — subsystems reset to defaults. Session/UI fields are unchanged; market quotes remain derived on load.
- Catalog JSON under `data/catalog/` remains read-only; saves never write there.
- Save/load available from the pause menu (in flight) and from HabitatScreen footer (while docked).

## Not yet implemented

- On-foot play: city roadmaps, trams, surface travel
- Named NPCs, dialogue trees, Dialogue Manager integration
- Unspace solution typing (integers shown as flavour only)
- Deeper N-space routes (n > 4)
- Ship hyperdrive translation
- Homing missiles, scatter pellet cones, combat game-over screen
- Paid workshop beyond parts inventory model
- Hull merchants beyond Proxima Habitat (Concord Scouts, Skyedge)
- Economic events (blockades, route friction overrides beyond `route_friction_delta` UI)
- Unknown/private Unspace routes
- Market contract depletion (depth is display-only)

Deferred design passes (propulsion fuel types, gravitic line, integrated sail): [backlog.md](backlog.md).

See `data/catalog/` and [setting docs](../setting/README.md) for implemented subset vs intended scope.
