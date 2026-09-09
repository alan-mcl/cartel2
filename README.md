# Cartel — 2D spaceship game

**Cartel** is a 2D near-orbit spaceship game built in Godot 4.7. Current version: **DEV**.

Fly with inertia, explore orbital space, dock at habitats, trade at the Exchange, outfit ships at the Shipyard, and jump between sectors via Unspace gates.

## Requirements

- [Godot 4.7+](https://godotengine.org/) (GL Compatibility renderer)

Godot binary used for development: `~/opt/Godot_v4.7.2-stable_linux.x86_64`

## Run

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --path /mnt/data/gitws/cartel2
```

Or open `project.godot` in the Godot editor and press **F5**.

The game opens at the **main menu** (version shown as **DEV**). Choose **New Game** to enter your callsign, pick a portrait, and choose a starting **background** kit. The default **Tester** background begins docked at **Proxima Habitat** with the full template fleet. Progress saves to `user://saves/slot_1.json` … `slot_3.json`.

## Controls

| Action | Keys |
|--------|------|
| Thrust | W, Up |
| Reverse / brake | S, Down |
| Rotate left | A, Left |
| Rotate right | D, Right |
| Boost | Shift (while thrusting) |
| Interact / Dock / Translate / Emerge | E |
| Pause | Escape (disabled while docked or jump overlay open) |
| Back (habitat UI) | Escape |
| Save / Load | Pause menu (in flight) or Save on habitat footer |
| Quit to menu | Pause menu or Menu on habitat footer |
| Undock | Terminal: select docked ship, then Undock |

## Core loop

1. Start at the **main menu** — New Game, Load, or Exit.
2. **New Game:** enter callsign, portrait, and background; default **Tester** kit begins docked at **Proxima Habitat** with the full template fleet.
3. Visit buildings from the habitat screen — **Terminal**, **Davidsons** (flavour), **Proxima Exchange** (buy/sell commodities), **Shipyard** (parts + assembly).
4. At the **Shipyard**, buy spare modules, drag them onto chassis slots to install (chassis fixed), inspect configuration and engineering budgets, refuel. Yard stock is grouped by module category tabs.
5. **Terminal** — select a docked ship and **Undock** to launch into **Proxima Sector** orbit beside the habitat ring.
6. Fly the orbital ring (slowly rotating) and visit the **Jump Gate** to pick **La Bella Vista Sector**, confirm **4-space** translation.
7. Navigate **4-space** through the undulating lattice to the **Exit Portal**, then `[E]` to emerge in La Bella Vista orbit near the jump gate.
8. Dock at **La Bella Vista Habitat**, use terminal and shipyard, jump back to Proxima.
9. **Save** progress from the pause menu or habitat footer.

## Project layout

```
assets/ui/fonts/       IBM Plex Sans/Mono (OFL)
assets/ui/locations/   Placeholder habitat/building art (SVG)
assets/ui/portraits/   Player portrait images (add PNG/WebP/JPG manually)
assets/ui/patterns/    Reusable themed UI pattern scenes
themes/                cartel_theme.tres (project default)
scripts/tools/         Theme builder, art generator
scripts/gameplay/      Catalog, session, ship assembly, save store, version
scripts/presentation/  Godot integration (ship, camera, world loader)
scripts/ui/            HUD, menus, UiRoot, habitat/shipyard screens
scenes/ui/             Full-screen habitat UI scenes
scenes/dev/            Developer-only scenes (theme showcase, ship assembly sandbox)
data/catalog/          JSON catalogs including commodities and markets
docs/                  Architecture, data model, setting bible
```

Regenerate placeholder art (runs Godot import for new SVG/PNG assets):

```bash
python3 scripts/tools/generate_placeholder_art.py
```

If chassis sprites or player portraits fail to load after adding art manually, run:

```bash
godot --path . --import --headless --quit
```

Drop portrait images into `assets/ui/portraits/` (PNG, WebP, or JPG). They appear in the New Game picker after import.

Rebuild UI theme after token changes:

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --headless -s res://scripts/tools/build_cartel_theme.gd
```

Open the theme developer showcase:

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --path /mnt/data/gitws/cartel2 \
  --scene res://scenes/dev/theme_showcase.tscn
```

Open the ship assembly sandbox (no economy, fitting rules only):

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --path /mnt/data/gitws/cartel2 \
  --scene res://scenes/dev/ship_assembly_sandbox.tscn
```

In the editor, open either scene and press **F6** to run it standalone. **F5** still launches the full game.

## Checks

Agents and contributors should run the local gate after GDScript or catalog changes:

```bash
GODOT=~/opt/Godot_v4.7.2-stable_linux.x86_64 ./scripts/ci/check.sh
```

This validates ship templates and catalog references, imports assets, runs Godot `--check-only` on gameplay/presentation/ui scripts, and executes headless unit tests. See [AGENTS.md](AGENTS.md) for project conventions.

## Documentation

Specification and setting lore live in [`docs/`](docs/README.md):

- **Design** — architecture and JSON data model for this game
- **Setting** — planets, corporations, ships, and equipment (working bible)

## Versioning

Game version is defined in `scripts/gameplay/game_version.gd` (`GameVersion.VERSION`, currently **DEV**). Saves include a `game_version` field for diagnostics; save schema version is separate (`SaveStore.SAVE_VERSION`).

## Placeholders

- Location art under `assets/ui/locations/` are placeholders; replace with final paintings when ready.
- No named NPCs or dialogue yet — store interactions only.
- Market stock is catalog-defined and restocks each session (not persisted).
- Only **4-space** is playable; deeper N-space routes are future work.
- Hull merchants on Proxima Habitat only (Concord Scouts used ships, Skyedge chassis frames).
