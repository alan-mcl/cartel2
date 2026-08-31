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
| Interact / Dock / Translate | E |
| Pause | Escape (disabled while docked or translating) |
| Undock / Cancel jump | Esc or button |

## Prototype loop

1. Launch in the **Flare-ON SS** in **Proxima Sector**; a **Pegasus P101** is parked at Proxima Habitat.
2. Fly toward **Beacon 3** and salvage the **Derelict Wreck** (+d850).
3. Dock at **Proxima Habitat** — your current ship is parked there.
4. Visit **Habitat Workshop** to swap chassis, engine, or armour on any docked ship (free).
5. Fly to the **Jump Gate** and translate to **Bela Sector** (listed route; no typing puzzle yet).
6. Explore Bela orbit, dock at **Bela Orbital Habitat**, salvage the drift wreck, and jump back to Proxima.
7. **Undock** and choose which ship to launch when multiple are parked at a habitat.

## Project layout

```
assets/               SVG/PNG art (see below)
scripts/gameplay/     Ship motion/state, JSON catalog loader, assembler, owned fleet
scripts/presentation/ Godot integration (ship, camera, world loader)
scripts/tools/        Placeholder art generator
scripts/ui/           HUD, pause, location, and jump overlays
scenes/               Main scene and world objects
data/catalog/         JSON ship, player, habitat, sector, world, and interactable catalogs
```

## Graphics assets (SVG + PNG)

| Format | Use for |
|--------|---------|
| **SVG** | Ships, stations, gates, beacons, markers, simple environmental objects |
| **PNG** | Starfield textures, planet limb, backgrounds, painterly effects |

```
assets/
  ships/chassis/     Per-chassis hull SVG (referenced from chassis.json)
  ships/fx/          Thrust and other ship effects
  world/             Habitat, gate, beacon, wreck, debris (SVG); planet limb (PNG)
  space/             Tileable starfield PNG layers
  ui/                Reserved for future HUD icons
```

Chassis entries in `data/catalog/chassis.json` include a `sprite` path:

```json
"sprite": "res://assets/ships/chassis/flare_on_chassis.svg",
"hull_color": "#5ee0ff"
```

Workshop chassis swaps update both stats and hull sprite. Replace art by overwriting files in place (update the path in JSON if you switch format, e.g. SVG to painted PNG).

Regenerate placeholder art:

```bash
python3 scripts/tools/generate_placeholder_art.py
```

Then reimport in Godot (open the project or run with `--import`).

## Player fleet (JSON)

Owned ship **instances** live in `data/catalog/player.json`:

```json
{
  "starting_sector": "proxima",
  "credits": 3000,
  "ships": [
    {
      "id": "flare_on_ss_1",
      "name": "Flare-ON SS",
      "template_id": "flare_on_ss",
      "chassis_id": "flare_on_chassis",
      "engine_id": "mark_3_fusion",
      "armour_id": null,
      "location": "aboard"
    },
    {
      "id": "pegasus_p101_1",
      "name": "Pegasus P101",
      "template_id": "pegasus_p101",
      "chassis_id": "pegasus_chassis",
      "engine_id": "mark_1_fusion",
      "armour_id": "chitanium_5mm",
      "location": "proxima_habitat"
    }
  ]
}
```

- `starting_sector` — sector id loaded on game start (from `sectors.json`)
- `location: "aboard"` — the ship you fly in orbit
- `location: "proxima_habitat"` — parked at the habitat (ships stay at their parked habitat when you jump sectors)
- Docking parks your current ship at the habitat; undocking lets you pick which parked ship to launch

## Ship modules (JSON)

| File | Contents |
|------|----------|
| `chassis.json` | Hull frames: mass, hits, cargo, maneuver, hull color, sprite |
| `engines.json` | Engines: mass, thrust, max speed, boost multiplier |
| `armour.json` | Armour plates: mass, hits |
| `ships.json` | Ship templates (reference only for owned instances) |

Flight stats are derived by `ShipAssembler` from each owned ship's current module ids. Workshop swaps update those ids immediately (no cost in this prototype).

## Sectors, worlds, and interactables (JSON)

Orbit layouts and jump travel are data-driven.

| File | Contents |
|------|----------|
| `sectors.json` | Sector identity, orbit name, play bounds, spawn point, objective, Unspace `mappings` |
| `worlds.json` | Orbital entities per sector (habitats, gates, beacons, wrecks, debris, planet limb) |
| `interactables.json` | Interactable definitions keyed by id (`inspect`, `salvage`, `dock`, `translate`) |

**Sector mappings** define jump routes shown at translate gates:

```json
"mappings": [
  { "target": "bela", "solution": 42, "label": "Bela Sector" }
]
```

The `solution` value is stored for a future Unspace typing puzzle; this prototype lists routes and translates immediately.

**World entity** example in `worlds.json`:

```json
{
  "id": "proxima_habitat_obj",
  "kind": "habitat",
  "position": { "x": -1200, "y": -350 },
  "label": "Proxima Habitat",
  "interactable": "proxima_habitat"
}
```

Kinds: `habitat`, `jump_gate`, `beacon`, `wreck`, `debris`, `planet_limb`. Optional fields: `rotation`, `scale`, `sprite`, `modulate`.

To add an orbit object: add an interactable entry if needed, add the entity to the sector's list in `worlds.json`, and ensure the `kind` maps to an existing world scene in `WorldLoader`.

The dust ring is generated from each sector's `play_bounds` at load time.

## Habitat and buildings (JSON)

| File | Contents |
|------|----------|
| `habitats.json` | Habitats: name, default building, list of building ids |
| `buildings.json` | Buildings: name, kind, short description |

**Habitat Workshop** (`kind: "workshop"`) shows docked ships and module swap buttons from the catalogs. Both Proxima and Bela habitats include a workshop.

To add a building: entry in `buildings.json`, then add its id to the habitat's `buildings` array in `habitats.json`.

## Placeholders

- SVG/PNG placeholders are generated; replace with final art when ready.
- Unspace solution typing is not implemented yet (`solution` on mappings is stored only).
- Habitat buildings are menu-only; no on-foot interiors.
- Merchants are flavour-only (sales closed).
- No save/load for fleet or sector position.

## Next gameplay improvements

1. **Unspace puzzle** — type the solution integer to unlock routes.
2. **Paid workshop stock** — modules cost credits; limited inventory per station.
3. **NPC traffic** — a few drifting ships or tugs to make space feel alive.
4. **Fuel or heat management** — lightweight constraint that makes boost and long burns matter.
