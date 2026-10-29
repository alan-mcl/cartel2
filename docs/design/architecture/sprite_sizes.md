# Sprite size catalog

Production dimensions for Cartel art assets. Use this when authoring or refreshing SVG/PNG files so **on-disk size matches in-flight size** - no compensating for camera zoom or import scale in the canvas.

Reference viewport: **1920×1080**. Flight camera zoom: **0.72** (`scripts/presentation/follow_camera.gd`).

---

## Production rules

### 1 SVG pixel = 1 world unit

- Keep Godot import **`svg/scale=1.0`** on all chassis and world SVGs.
- Player and NPC hull `Sprite2D` nodes use **`scale = (1, 1)`** at configure time.
- Camera zoom is presentation only. Do **not** shrink SVG canvases to “fit” zoom 0.72.

### Nose-up, origin-centered

- Set `width` and `height` to match the `viewBox` extent.
- Standard viewBox: **`-W/2 -H/2  W  H`** (rotation pivot at SVG `(0,0)` = texture center).
- Place the desired spin point at SVG `(0,0)` by translating geometry - do not compensate with a shifted `viewBox` alone.
- **Nose points toward −Y** (up on screen when facing default).
- Collision hulls are derived from SVG primitives via `HullHitbox` (`scripts/presentation/hull_hitbox.gd`). Keep `width`, `height`, and `viewBox` in sync. Put paint in `style` attributes; remove conflicting presentation-attribute leftovers (`fill="#…"` on the same element as `style="fill:…"`).

### Clear border (5 px)

- **Max 5 px** transparent padding on **every edge** of hull sprites.
- Hull paint lives in the inner **`(W − 10) × (H − 10)`** box.
- Aspect ratio is part of the silhouette (dart vs saucer vs block freighter).

### Colour

- SVG paint owns colour. Hull sprites render at `Color.WHITE` (no `hull_color` modulate). See [architecture.md](architecture.md#graphics-convention).

### Known runtime exceptions (do not bake into art)

| Effect | Where | Value |
|--------|-------|-------|
| Distant traffic hulls | `traffic_director.gd` | `scale = 0.65` |
| Starfield near layer | `starfield.gd` | tile scale `1.15` |
| Planet disc on screen | `planet_backdrop.gd` | `sprite.scale = diameter / 1024` (catalog `diameter` = 2000 → ~1.95× viewport tex) |

---

## Chassis hulls (SVG)

Paths: `assets/ships/chassis/<id>.svg` - referenced from `data/catalog/chassis.json`.

### Scale rule

**Anchor:** Pegasus canvas **70×70**, catalog mass **8.5**.

```
longest_axis = round_to_even(70 × mass / 8.5)
```

Apply the chassis class aspect ratio to get width and height. Pegasus is **square**; all other hulls keep their class silhouette (dart, saucer, flat fighter, long interceptor, gunship block).

At zoom 0.72 on 1080p: Pegasus ≈ **50 screen px**; Flare-ON ≈ **19 px**; Wolff ≈ **59 px**.

| Chassis id | Name | Mass | Longest (even) | Aspect | **Author at (W×H)** | Inner paint |
|------------|------|------|----------------|--------|---------------------|-------------|
| `flare_on_chassis` | Flare-ON | 3.2 | 26 | 3:4 dart | **20×26** | 10×16 |
| `juno_chassis` | Juno | 5.0 | 42 | ~0.70 scout | **30×42** | 20×32 |
| `krypton_chassis` | Krypton | 6.0 | 50 | 3:2 saucer | **50×34** | 40×24 |
| `silhouette_chassis` | Silhouette | 6.8 | 56 | ~7:3 flat | **56×24** | 46×14 |
| `mantis_chassis` | Mantis | 3.0 | 24 | ~1:2 dart | **12×24** | 8×20 |
| `ave_chassis` | Ave | 3.0 | 24 | ~7:6 compact dart | **28×24** | 22×20 |
| `dragon_chassis` | Dragon | 7.5 | 62 | ~3:7 interceptor | **26×62** | 16×52 |
| `pegasus_chassis` | Pegasus | 8.5 | 70 | square | **70×70** | 60×60 |
| `wolff_chassis` | Wolff | 10.0 | 82 | 8:5 gunship | **82×52** | 72×42 |

**Example SVG header (Pegasus):**

```xml
<svg xmlns="http://www.w3.org/2000/svg"
     width="70" height="70"
     viewBox="-35 -35 70 70">
  <!-- hull geometry in inner 60×60; nose toward -Y -->
</svg>
```

Same chassis SVGs appear in habitat/shipyard UI (`LocationArt` `TextureRect`, fit inside a 160 px-tall 16:9 frame). Flight size is authoritative; UI scales down.

---

## Ship FX (SVG)

| Asset | Path | POC | **Author at** | Notes |
|-------|------|-----|---------------|-------|
| Thrust alignment | `assets/ships/fx/thrust.svg` | 32×32 | **20×24** | Stern anchor only; flight exhaust is procedural per `engine_type` (`EngineExhaust`) |
| Mass driver round | `assets/ships/fx/mass_driver_round.svg` | 16×16 | **16×16** | Keep |
| Laser / cyber beams | - | Line2D | - | Procedural; no sprite |

### Thrust attachment

The thrust SVG is hidden at runtime; `EngineExhaust` draws from the fitted engine with the **nozzle** at parsed **visual stern** + a small aft clearance (all plumes extend in **+Y**). Align the hidden **ThrustFlame** **plume base** (not the texture edge) with the hull **visual stern** (max Y of parsed hull geometry in world space):

```
position.y = stern_extent(hull) - thrust_plume_base_offset
```

For origin-centered art where stern matches canvas bottom, this equals `hull_height / 2 - thrust_plume_base_offset`. Example (Pegasus 70×70): `35 - 8 = **27**`.

`thrust_plume_base_offset` is parsed from thrust SVG art (currently **8** on the 32×32 placeholder).

**Runtime:** `HullHitbox.apply_hull_and_thrust()` leaves hull `Sprite2D.offset` at zero and sets thrust Y from the visual stern (player, NPC, distant traffic). Parsed geometry is cached per sprite path.

---

## World landmarks (SVG)

Paths under `assets/world/`. Referenced from `data/catalog/worlds.json` entity `sprite` fields. Stations should read clearly **larger than the biggest hull** (Wolff longest axis **82 px**).

| Asset | Path(s) | POC | **Author at (W×H)** | Role |
|-------|---------|-----|---------------------|------|
| Proxima habitat | `world/habitat_proxima.svg` | 280×180 | **480×320** | Dockable; ~4× Pegasus footprint |
| Bela habitat | `world/habitat_bela.svg` | 280×180 | **480×320** | Dockable |
| Generic habitat (unused) | `world/habitat.svg` | 260×160 | **480×320** | Align if revived |
| Jump gate | `world/jump_gate.svg` | 240×240 | **400×400** | Sector landmark |
| Torus orbital | `world/orbitals/torus.svg` | 140×140 | **200×200** | Ring station |
| Yard | `world/orbitals/yard.svg` | 160×100 | **240×150** | Shipyard silhouette |
| Tank farm | `world/orbitals/tank_farm.svg` | 150×110 | **220×160** | Fuel storage |
| Array | `world/orbitals/array.svg` | 130×130 | **180×180** | Sensor / comms |
| Tower | `world/orbitals/tower.svg` | 90×160 | **100×220** | Tall spar |
| Platform | `world/orbitals/platform.svg` | 170×90 | **240×120** | Wide deck |
| Debris rock | `world/debris.svg` | 80×64 | **16×20** | Smaller than Flare-ON; shootable catalog rocks |

World entity `modulate` in JSON still tints some sprites today. For a clean SVG pipeline, author final colour in the file and set catalog `modulate` to `#ffffff` when replacing placeholders.

---

## PNG - space and planets

| Asset | Path | Current | **Author at** | Usage |
|-------|------|---------|---------------|-------|
| Starfield far | `assets/space/stars_far.png` | 512×512 | **512×512** | Seamless tile; parallax 0.08; repeated around the camera in flight |
| Starfield near | `assets/space/stars_near.png` | 512×512 | **512×512** | Seamless tile; runtime scale 1.15 - do **not** bake 1.15 into the PNG; repeated around the camera in flight |
| Planet albedo | `assets/world/planets/<sector_id>_albedo.png` | 2048×1024 placeholders | **2048×1024** (preferred) or **1024×512** min | Equirectangular 2:1; wired in `worlds.json` `planet.albedo` |
| Planet night lights | `assets/world/planets/<sector_id>_night.png` | 2048×1024 placeholders | Same as albedo | Same pixel size and equirect UV as albedo; **RGB emission** (black = none). Shader adds `texture * night_emission_strength` on the night side only. Generate from albedo: `python3 scripts/tools/planet_night_from_albedo_photorealistic.py assets/world/planets/<sector>_albedo.png --density 0.4 -o assets/world/planets/<sector>_night.png` (requires `pip install pillow`). The same run writes `<sector>_night_habitations.json` beside the night PNG. |
| Planet disc (legacy) | `assets/world/planet.png` | 512×512 | - | **Unused** for globe mesh; do not replace as a flat disc |

Globe on-screen size comes from catalog **`planet.diameter`** (currently **2000** world units for all sectors). The 3D mesh renders in a **1024** px SubViewport (throttled refresh in flight) and is scaled to `diameter / 1024`. Albedo and night PNGs remain **2048×1024** equirectangular maps. Replace PNGs in place (same filename); **`planet.modulate` does not tint mapped albedo** (procedural fallback only). Missing planet placeholders only: `python3 scripts/tools/generate_placeholder_art.py` (skips any file that already exists, including authored albedo and night maps). It does not write habitations sidecars.

`planet_night_from_albedo_photorealistic.py` keeps cities, villages, and highway lamps equatorward of 60° latitude. Weight is full at the equator and thins toward that cap. The tool writes one anchor per distinct large metro (`radius >= 0.010` of the map width), largest first, stopping at `round(24 × density)`. A smaller centre that lies inside a larger centre's angular radius (`360 * radius_px / width` degrees, measured on the sphere) is the same agglomeration and is omitted, including across the equirect seam. A raw population ratio is raised to the power that maps Tycho (3.5 billion) onto one third and leaves Proxima (60 billion) at 1, so those densities label 8 and 24 City-Malls. La Bella Vista sits on the same curve. Sidecar fields are `sector_id`, `seed`, `density`, `width`, `height`, and `anchors`. Each anchor has `name`, `u`, `v`, `radius_px`, and `local`. `u` and `v` are equirectangular texture coordinates with the origin at the top-left of the PNG (`u = (x + 0.5) / width`, `v = (y + 0.5) / height`). `local` is the matching unit direction in Godot `SphereMesh` space: `v = 0` is the north pole (`+Y`), `v = 1` is the south pole (`-Y`), `u = 0` faces `+Z`, and `u` increases toward `+X` (`x = sin(2π u) sin(π v)`, `y = cos(π v)`, `z = cos(2π u) sin(π v)`). The planet shader samples `UV` with no V flip, and the globe camera sits on `+Z` looking toward the origin.

A label rotates `local` with the planet root (`Basis.from_euler(Vector3(pitch, yaw, 0))`, Godot's default YXZ order) and projects the orthographic disc:

```text
p = basis * local
visible when p.z > ~0.08
world_pos = Vector2(p.x, -p.y) * (diameter / 2.05)
```

`2.05` is the backdrop camera size. The sphere is slightly inset in the viewport, so that scale keeps the label on the disc. The flight HUD and the system render tester draw one label per anchor while that point faces the camera, on the day side and the night side. The name is centred on the projected point plus the planet's position on the flight plane, so the text stays on the city at any camera zoom. After regenerating a night PNG, reimport (`godot --path . --import --headless --quit`) so the globe uses the same map as the sidecar.

When the albedo stem matches a sector id, anchor names are that sector's `city_malls` in list order, largest metro first. Metros beyond the list are appended to `city_malls` as `CM-N`. `N` continues from the highest `CM-N` already in that sector, so a later run keeps existing placeholders. Existing entries stay in place, including placeholders later given real names. An albedo stem that is not a sector id still writes anchors named `CM-1` onward and leaves `sectors.json` unchanged. Real names for `CM-N` are filled in by hand.

---

## PNG / SVG - UI art

| Asset | Path pattern | Current | **Author at** | Display |
|-------|--------------|---------|---------------|---------|
| Location / building art | `assets/ui/locations/*.png` | 640×360 | **640×360** (or **1280×720** optional) | 16:9; `LocationArt` frame min-height 160 px |
| Corporation logos | `assets/ui/corps/logos/<callsign_prefix>.png` | 160 px tall | **160 px tall** (width proportional) | 1:1 on corporate building banners; right edge flush, vertically centred, cropped to the 160 px header |
| Chassis UI header | `assets/ui/ships/<chassis_id>.png` | 640×360 | **640×360** (or **1280×720** optional) | 16:9 banner via `LocationArtFactory.create_banner()` (cover + left fade); Shipyard hosts above stats scroll |
| Module category icon | `assets/ui/modules/<category>.png` | 64×64 | **64×64** | One PNG per module `category`; list rows at 24 px |
| Pilot portraits | `assets/ui/portraits/pN.png` | 3:4 | **120×160** | Same height as habitat header banner (`LocationArt` header min-height **160 px**); width **120** (3:4). `PortraitTextureRect` uses that box in New Game and habitat. Mipmaps + linear filter if exporting larger. |

Building art paths live in `data/catalog/buildings.json` and `habitats.json` (`art` field). Chassis headers live in `data/catalog/chassis.json` (`header` field); world hull SVGs stay in `sprite`. Placeholder PNGs: `python3 scripts/tools/generate_ui_ship_module_art.py` (skip-if-present).

---

## Inkscape and Godot import checklist

- Use **even integer** `width` / `height` where possible.
- **`svg/scale=1.0`** in `.import` sidecar (default for new imports).
- **`editor/convert_colors_with_editor_theme=false`** (already set on chassis imports).
- Prefer flat fills, linear/radial gradients, and explicit `style` paint. Avoid Inkscape-only filters, mesh gradients, and non-normal blend modes (ThorVG may drop them).
- After adding or resizing SVGs: `godot --path . --import --headless --quit`
- `scripts/tools/generate_placeholder_art.py` writes a file only when that path is absent. It does not replace authored hulls, starfields, or planet maps.

---

## Quick reference - all author-at sizes

| Category | Dimensions |
|----------|------------|
| Hulls | 20×26 … 82×52 (Pegasus anchor 70×70; see table above) |
| Thrust FX | 20×24 |
| Mass driver | 16×16 |
| Habitats | 480×320 |
| Jump gate | 400×400 |
| Orbitals | 100×220 … 240×240 |
| Debris rock | 16×20 |
| Star tiles | 512×512 |
| Planet maps | 2048×1024 (2:1) |
| Location art | 640×360 (16:9) |
| Portraits | 120×160 |
