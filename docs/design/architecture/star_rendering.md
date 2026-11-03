# Star rendering

This document records **what Cartel draws today** for stars and skies during near-orbit flight. It is the working baseline for further star work. Lore about individual systems stays in [planets.md](../../setting/planets.md); code paths and load order are summarised in [architecture.md](architecture.md).

## Scope

Cartel flight is **2D top-down** with a layered backdrop. Stars appear in three distinct roles:

| Role | Purpose | Tied to catalog? |
|------|---------|------------------|
| **Starfield** | Infinite parallax wallpaper behind the play space | No — same tile art in every 3-space sector |
| **Local star** | The sector’s sun: bright disc, corona, and driver for planet day/night | Yes — `sectors.json`, `stars.json`, `worlds.json` |
| **Companion stars** | Extra suns on the same sky ring (binaries, bright neighbours, story objects) | Partly — catalog stars or presentation-only overrides |
| **Parent body** | Distant gas giant or similar for moon sectors | Yes — `worlds.json` `parent_body`; not a star shader |

**Unspace** transit uses a dimmed starfield tint and does not spawn a local star. Volatile survey sites may spawn zero or one local star from grant-time data.

Positions for the local star (and backdrop layout that depends on it) are **visit-random** and are **not saved** between sessions.

**Physical distance** (`star_distance_au`) and **sky position** (annulus 7000–12000) are independent: AU drives apparent size and irradiance; screen position is layout only.

## Background starfield

The main scene mounts a **Starfield** node (`starfield.gd`, `starfield_tiling.gd`):

- Two layers — **far** and **near** — each built from a seamless **512×512** PNG (`assets/space/stars_far.png`, `assets/space/stars_near.png`).
- **Parallax**: far layer offset `0.08 ×` camera anchor; near layer `0.22 ×`. The near layer is drawn at **1.15×** texture scale (scale is applied at runtime, not baked into the PNG).
- Each frame, tiles are placed on a lattice around the camera so the player never sees an edge.
- In **3-space**, the field uses a neutral white modulate. In **Unspace**, both layers switch to a low-opacity blue-violet wash (`WorldController` / `set_unspace_mode`).

The starfield does **not** list named stars from `stars.json` and does not change per `star_system`. It stands in for the general galactic background.

## Physical size and brightness

Resolution lives in **`StarAppearance`** (`star_appearance.gd`); **`LocalStar`** applies the result to the shader.

### Apparent diameter

Small-angle form (degrees):

`angular_diameter_deg = 0.533 × radius_solar / distance_au`

World disc radius (presentation scale):

`physical_disc_radius = star_size_scale × radius_solar / distance_au`

Default **`star_size_scale`** is **24** (Sun at 1 AU → disc radius 24 world units). Luminosity and temperature do **not** change physical disc size.

Optional **`disc_radius`** on a world or presentation-only companion overrides the **displayed** disc only; **`physical_disc_radius`** is still computed for reference.

### Irradiance and on-screen brightness

Physical irradiance (also used for the planet):

`irradiance = luminosity / distance_au²`

The visible star uses a compressed tone map on that value:

`apparent_brightness = 1 − exp(−clamp(brightness_scale × irradiance^brightness_exponent, min, max) × exposure)`

Planet **`PlanetBackdrop.set_sun`** receives **raw irradiance** and temperature colour from **`LocalStar.get_illumination()`**, not the tone-mapped brightness.

Missing **`radius_solar`**, **`luminosity`**, or **`temperature_k`** fall back to 1.0, 1.0, and 5800 K. **`spectral_class`** does not invent those numbers; it selects visual presets only.

## Local star (primary sun)

Each loaded 3-space sector (and volatile sites that grant a star) spawns one **LocalStar** node (`local_star.gd`, shader `shaders/local_star.gdshader`).

### Shader layers

Additive **canvas_item** shader on a white quad scaled to **`2 × disc_radius × corona_radius_multiplier`** world units:

1. **Disc** — temperature colour, saturation, limb darkening, subtle procedural surface variation (fades on small discs). Drawn with **`blend_mix`** and **alpha 1** across the photosphere so the starfield does not show through. Limb darkening tints rgb only. The corona uses the same mix blend outside the disc (additive glow cannot cover the background).
2. **Inner glow** — concentrated halo just outside the disc (weaker than the disc edge so the body reads solid).
3. **Outer corona** — radial falloff; brightness follows **`apparent_brightness`** so high-luminosity stars stay visible when the physical disc is tiny.
4. **Optional activity** — restrained **flares** for emission-type spectral classes (e.g. `…Ve`); **diffraction spikes** off unless explicitly enabled on the star data.

**`spectral_class`** (and optional world **`preset`**) pick default corona multiplier, limb strength, and activity flags. Giants (luminosity class I–III in the class string, or **`radius_solar ≥ 5`**) use a broader corona preset on top of the spectral letter.

Draw order: **`z_index -40`** (in front of the planet backdrop at `-50` so the sun reads clearly at the rim of the sky).

### Placement

On each sector load, `WorldLoader` picks a position on an annulus:

- Radius **7000–12000** world units from the origin (planet at centre).
- At least **800** units from the jump gate.
- Prefer directions where the star is **not** almost behind the planet as seen from the dock reference (habitat on the orbital ring); up to 48 random tries, then best-effort scoring.

### Data merge

| Source | Fields used for rendering |
|--------|---------------------------|
| `sectors.json` | `star` (catalog name, if set), `star_system`, **`star_distance_au`** |
| `stars.json` | **`luminosity`**, **`temperature_k`**, **`radius_solar`**, **`spectral_class`** |
| `worlds.json` → **`star`** | Optional **`disc_radius`**, **`preset`**, **`flares_enabled`**, **`spikes_enabled`**; temperature/luminosity hints until merged from catalog |

`WorldLoader._presentation_star_block` overwrites world **`luminosity`**, **`temperature_k`**, and **`spectral_class`** from `stars.json` when the primary catalog star resolves.

### Planet lighting

Only the **primary** local star feeds **`PlanetBackdrop.set_sun`** today. **`get_illumination()`** returns world position, raw irradiance, colour, distance, and luminosity for future multi-star lighting.

Companion stars and the parent body do **not** alter the planet terminator.

## Companion stars

Optional **`companion_stars`** on a `worlds.json` row spawn additional **LocalStar** nodes using the same renderer:

- **Sky position**: same annulus distance as the primary, bearing **primary angle + `separation_deg`**.
- **Catalog entry**: `{ "star": "<stars.json name>", "separation_deg": … }` — full catalog facts; disc size from **`radius_solar / distance_au`** (companion **`distance_au`** optional on the entry, else the sector primary distance).
- **Presentation-only**: `{ "name", "temperature_k", "luminosity", "disc_radius", "separation_deg" }` (e.g. **The Widow** at Tycho).

Companions are target-lockable **stars**; they are not second light sources for the globe.

## Parent body (non-star backdrop)

Moon sectors may define **`parent_body`**. **SkyParentBody** renders at **`z_index -60`**. **Known gap:** parent-body shading is not aligned to the primary star’s world position ([backlog B4](backlog.md)).

## Volatile translation sites

Grant-time star setup may enforce a minimum **`disc_radius`** for visibility; otherwise the same **`StarAppearance`** path applies.

## Draw order (back → front)

1. Starfield far (`-200`) → near (`-100`) → parent body (`-60`) → planet (`-50`) → local star and companions (`-40`) → gameplay entities.

## Out of scope (today)

- Per-system **starfield** tiles or constellations.
- **Multi-star** planet illumination (interface prepared via **`get_illumination()`**).
- Ephemeris or time-varying binary separation.
- Parent-body light alignment with the local star.

## Inspection and tuning

- **Star rendering harness** — `./scripts/dev/star_rendering_harness.sh` (pick any catalog star, AU distance, companions; **F6** on `star_rendering_harness.tscn`)
- **System render tester** — `./scripts/dev/system_render_tester.sh`
- **Parent body harness** — `./scripts/dev/parent_body_harness.sh`

Implementation: `star_appearance.gd`, `local_star.gd`, `world_loader.gd`, `planet_backdrop.gd`, `tests/test_star_appearance.gd`, `tests/test_sky_backdrop.gd`.
