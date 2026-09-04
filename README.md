# Cartel — 2D spaceship prototype

Playable near-orbit prototype for **Cartel**, set in Proxima Sector. Fly a ship with inertia, explore orbital space, salvage wrecks, dock at habitats, trade at the Exchange, outfit ships at the Shipyard, and jump between sectors via Unspace gates.

## Requirements

- [Godot 4.7+](https://godotengine.org/) (GL Compatibility renderer)

Godot binary used for development: `~/opt/Godot_v4.7.2-stable_linux.x86_64`

## Run

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --path /mnt/data/gitws/cartel2
```

Or open `project.godot` in the Godot editor and press **F5**.

The game opens at the **main menu**. Choose **New Game** to enter your pilot name and callsign; you begin docked at **Proxima Habitat** with your starter fleet parked there. Progress saves to `user://saves/slot_1.json` … `slot_3.json`.

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

## Prototype loop

1. Start at the **main menu** — New Game, Load, or Exit.
2. **New Game:** enter pilot name and callsign; begin docked at **Proxima Habitat** with **Flare-ON SS** and **Pegasus P101** parked there.
3. Visit buildings from the habitat screen — **Terminal**, **Davidsons** (flavour), **Proxima Exchange** (buy/sell commodities), **Shipyard** (parts + assembly).
4. At the **Shipyard**, buy spare modules, drag them onto chassis slots to install (chassis fixed), inspect configuration and engineering budgets, refuel. Yard stock is grouped by module category tabs.
5. **Terminal** — select a docked ship and **Undock** to launch into **Proxima Sector** orbit.
6. Fly toward **Beacon 3** and salvage the **Derelict Wreck** (+d850).
7. Fly to the **Jump Gate**, pick **Bela Sector**, confirm **4-space** translation.
8. Navigate **4-space** to the **Exit Portal**, then `[E]` to emerge in Bela orbit.
9. Dock at **Bela Orbital Habitat**, use terminal and shipyard, jump back to Proxima.
10. **Save** progress from the pause menu or habitat footer.

## Project layout

```
assets/ui/fonts/       IBM Plex Sans/Mono (OFL)
assets/ui/locations/   Placeholder habitat/building art (SVG)
assets/ui/patterns/    Reusable themed UI pattern scenes
themes/                cartel_theme.tres (project default)
scripts/tools/         Theme builder, art generator
scripts/gameplay/      Catalog, session, ship assembly, save store
scripts/presentation/  Godot integration (ship, camera, world loader)
scripts/ui/            HUD, menus, UiRoot, habitat/shipyard screens
scenes/ui/             Full-screen habitat UI scenes
scenes/dev/            Developer-only scenes (theme showcase)
data/catalog/          JSON catalogs including commodities and markets
docs/                  Architecture, data model, setting bible
```

Regenerate placeholder art:

```bash
python3 scripts/tools/generate_placeholder_art.py
```

Rebuild UI theme after token changes:

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --headless -s res://scripts/tools/build_cartel_theme.gd
```

Open the theme developer showcase:

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --path /mnt/data/gitws/cartel2 \
  --scene res://scenes/dev/theme_showcase.tscn
```

## Documentation

Specification and setting lore live in [`docs/`](docs/README.md):

- **Design** — architecture and JSON data model for this Godot prototype
- **Setting** — planets, corporations, ships, and equipment (working bible)

## Placeholders

- Location art under `assets/ui/locations/` are placeholders; replace with final paintings when ready.
- No named NPCs or dialogue in this slice — store interactions only.
- Market stock is catalog-defined and restocks each session (not persisted).
- Only **4-space** is playable; deeper N-space routes are future work.
- Merchants beyond the Exchange are not implemented (Skyedge remains unused in Proxima visit list).
