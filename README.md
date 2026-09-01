# Cartel — 2D spaceship prototype

Playable near-orbit prototype for **Cartel**, set in Proxima Sector. Fly a ship with inertia, explore orbital space, salvage wrecks, dock at habitats, outfit ships at the workshop, and jump between sectors via Unspace gates.

## Requirements

- [Godot 4.7+](https://godotengine.org/) (GL Compatibility renderer)

Godot binary used for development: `~/opt/Godot_v4.7.2-stable_linux.x86_64`

## Run

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --path /mnt/data/gitws/cartel2
```

Or open `project.godot` in the Godot editor and press **F5**.

## Controls

| Action | Keys |
|--------|------|
| Thrust | W, Up |
| Reverse / brake | S, Down |
| Rotate left | A, Left |
| Rotate right | D, Right |
| Boost | Shift (while thrusting) |
| Interact / Dock / Translate / Emerge | E |
| Pause | Escape (disabled while docked; overlay pauses while picking route) |
| Undock / Cancel jump | Esc or button |

## Prototype loop

1. Launch in the **Flare-ON SS** in **Proxima Sector**; a **Pegasus P101** is parked at Proxima Habitat.
2. Fly toward **Beacon 3** and salvage the **Derelict Wreck** (+d850).
3. Dock at **Proxima Habitat** — your current ship is parked there.
4. Visit **Habitat Workshop** to swap chassis, engine, or armour on any docked ship (free).
5. Fly to the **Jump Gate**, pick **Bela Sector**, confirm **4-space** translation (known solution 42 shown as flavour).
6. Navigate **4-space**: fly past shear hazards and debris to the **Exit Portal**, then `[E]` to emerge in Bela orbit.
7. Explore Bela orbit, dock at **Bela Orbital Habitat**, salvage the drift wreck, and jump back to Proxima via 4-space.
8. **Undock** and choose which ship to launch when multiple are parked at a habitat.

## Project layout

```
assets/               SVG/PNG art (sprite paths live on chassis and world JSON)
scripts/gameplay/     Ship motion/state, JSON catalog loader, assembler, owned fleet
scripts/presentation/ Godot integration (ship, camera, world loader)
scripts/tools/        Placeholder art generator
scripts/ui/           HUD, pause, location, and jump overlays
scenes/               Main scene and world objects
data/catalog/         JSON ship, player, habitat, sector, world, and interactable catalogs
docs/                 Architecture, data model, and setting bible
```

Regenerate placeholder art:

```bash
python3 scripts/tools/generate_placeholder_art.py
```

Then reimport in Godot (open the project or run with `--import`).

## Documentation

Specification and setting lore live in [`docs/`](docs/README.md):

- **Design** — architecture and JSON data model for this Godot prototype
- **Setting** — planets, corporations, ships, and equipment (working bible; edit before catalogs catch up)

## Placeholders

- SVG/PNG placeholders are generated; replace with final art when ready.
- Unspace solution **typing** is not implemented yet (`solution` on mappings is shown as flavour only).
- Only **4-space** (lowest N) is playable; deeper N-space routes are future work.
- Ship **hyperdrive** translation is not implemented (jump gates only).
- Habitat buildings are menu-only; no on-foot interiors.
- Merchants are flavour-only (sales closed).
- No save/load for fleet or sector position.
