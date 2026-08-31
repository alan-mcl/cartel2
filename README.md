# Cartel — 2D spaceship prototype

Playable near-orbit prototype for **Cartel**, set in Proxima Sector. Fly a Flare-ON SS with inertia, explore a small orbital space, and salvage a derelict wreck.

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
| Interact | E |
| Pause | Escape |

## Prototype loop

1. Launch into Proxima near orbit.
2. Fly toward **Beacon 3** (objective in HUD).
3. Find the **Derelict Wreck** nearby.
4. Press **E** to salvage it (+d850).
5. Inspect Habitat, Jump Gate, or beacons and keep exploring.

## Project layout

```
scripts/gameplay/     Ship motion/state, JSON catalog loader, assembler
scripts/presentation/ Godot integration (ship, camera, world)
scripts/ui/           HUD and pause overlay
scenes/               Main scene and world objects
data/catalog/         JSON ship/component catalogs
data/interactables/   Interactable definitions (Godot resources)
```

## Ship data (JSON)

The player ship is assembled at runtime from JSON catalogs under `data/catalog/`:

| File | Contents |
|------|----------|
| `chassis.json` | Hull frames: mass, hits, cargo, maneuver class |
| `engines.json` | Engines: mass, thrust, max speed, boost multiplier |
| `armour.json` | Armour plates: mass, hits |
| `ships.json` | Ship loadouts: references to chassis, engine, armour, weapons |

The prototype player ship is `flare_on_ss` in `ships.json`, composed of:

- **Chassis:** `flare_on_chassis`
- **Engine:** `mark_3_fusion`
- **Armour:** none

Flight stats are derived at runtime by `ShipAssembler` from those modules. To experiment, edit a module's stats in JSON or change the loadout ids in `ships.json`, then relaunch.

Example loadout entry:

```json
{
  "id": "flare_on_ss",
  "name": "Flare-ON SS",
  "maker": "Holt-Winters Corp",
  "chassis": "flare_on_chassis",
  "engine": "mark_3_fusion",
  "armour": null,
  "weapons": []
}
```

## Placeholders

- All visuals are procedural shapes (no final art).
- Jump gate is inspect-only (no Unspace travel).
- Single salvage interaction; no economy simulation.
- No save/load.
- Weapons slot exists in ship JSON but has no weapon catalog yet.

## Next gameplay improvements

1. **Dock at Proxima Habitat** — transition from orbit to a simple station interior or menu.
2. **NPC traffic** — a few drifting ships or tugs to make space feel alive.
3. **Fuel or heat management** — lightweight constraint that makes boost and long burns matter.
