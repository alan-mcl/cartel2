# Procedural asteroid renderer

Runtime debris and sample art today still use flat SVG placeholders ([sprite_sizes.md](sprite_sizes.md)). **AsteroidView** is a seeded canvas shader that draws a lit rocky body on a transparent background, in the same presentation family as [SkyParentBody](sky_parent_body.gd) (white quad + `canvas_item` shader).

Flight **debris** and retrieval **asteroid_sample** contacts use **AsteroidView** in [`debris_rock.tscn`](../../../scenes/world/debris_rock.tscn). Shape seed is `absi(entity_id.hash())`; composition comes from the same seed via `composition_for_seed` (**carbonaceous 65%**, **stony 30%**, **metallic 4%**, **icy 1%**). World size is **80** px. Lighting follows the sector **LocalStar** (same canvas bearing as [`SkyParentBody`](sky_parent_body.gd) / [`PlanetBackdrop`](planet_backdrop.gd)): star world position and `get_irradiance()` applied when debris spawns and on the target-lock chit preview.

## Components

| Piece | Path | Role |
|-------|------|------|
| Shape | `scripts/presentation/asteroid_shape.gd` | Deterministic ellipsoid + lobes + craters; composition presets |
| View | `scripts/presentation/asteroid_view.gd` | `Node2D` + `Sprite2D` quad; `configure(seed, composition, world_size)`; `set_sun(direction, intensity)` |
| Shader | `shaders/asteroid.gdshader` | Orthographic ray cast, albedo noise, directional light, soft alpha |
| Harness | `scenes/dev/asteroid_harness.tscn` | Interactive review at 20 / 72 / 256 px |

## Seed contract

- **Integer seed** drives `RandomNumberGenerator` for ellipsoid-scaled facet planes (8–12), crater count (0–4), chip amplitude, and crater placement.
- The same `(seed, composition)` pair always yields the same shape uniforms.
- Different seeds are intended to produce visibly different silhouettes, not near-duplicate ellipsoids.

## Shape model

1. **Faceted hull** — up to 12 cutting planes. Per direction, radius is the minimum `offset / dot(direction, normal)` (dot clamped to 0.2), giving flat faces and sharp creases.
2. **Surface chips** — ridged 3D noise (`1 - |2n - 1|`, frequency 5) adds small jagged bite without dominating the silhouette; scaled by composition `relief_scale`.
3. **Craters** — compact bowls (0.08–0.22 rad) with a flat floor, steep inner wall, raised lit rim, and ±12% angular wobble; shading comes from geometry only (no painted crater discs).

`AsteroidShape.radius(direction, params)` mirrors the shader’s `support_radius` for tests and `radius_max` fitting.

## Compositions

Renderer presets only (not catalog lore): `stony` (default), `carbonaceous`, `metallic`, `icy`. Each sets a two-colour palette, specular strength, crater depth scale, and relief scale.

## Lighting

`set_sun` passes a **normalised** `vec3` light direction and **physical irradiance** (`LocalStar.get_irradiance()` in flight), matching [`PlanetExposure`](planet_exposure.gd) / planet globes: night-side fill from scaled stellar flux, day side from irradiance × half-Lambert wrap, then **display exposure** (`2.5 / irradiance^0.75`, with a modest extra boost below **0.05** irradiance for small-sprite readability) and chroma-preserving Reinhard tone mapping. Default harness key light is upper-left in canvas space (`Vector3(-0.6, -0.5, 0.62)`) at **1 AU** irradiance.

## Harness

```bash
./scripts/dev/asteroid_harness.sh
```

Or **F6** on `asteroid_harness.tscn`.

- Large **primary** rock plus a **gallery** row of related seeds at the selected size preset (20 px debris, 72 px sample, or 256 px).
- **SubViewport** previews at 20 and 72 px, nearest-neighbour upscaled in the panel (honest in-game pixel read).
- Optional **flight camera zoom** (0.72) to match [follow_camera.gd](../../../scripts/presentation/follow_camera.gd).
- Pan (LMB), wheel zoom, **F** / **Frame**.

Headless smoke: [`scripts/dev/smoke_scenes.gd`](../../../scripts/dev/smoke_scenes.gd) instantiates the harness and checks that `World/PrimaryAsteroid` spawns.

## Follow-on

- Optional baked PNG export for catalog paths without changing the analytic shader path.

Unit tests: `TestAsteroidShape` in [`tests/test_asteroid_shape.gd`](../../../tests/test_asteroid_shape.gd) (CPU shape only; visual acceptance is the harness).
