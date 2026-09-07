# Cartel UI theme

Corporate information-system visual language for the Godot prototype: charcoal surfaces, off-white text, amber accent. Designed at **1920×1080** with compact Bloomberg-style density — fonts do not scale up to fill the viewport.

## Canonical resources

| Resource | Purpose |
|----------|---------|
| `themes/cartel_theme.tres` | Project default theme (committed generated output) |
| `scripts/tools/build_cartel_theme.gd` | Token-driven theme generator |
| `assets/ui/fonts/` | IBM Plex Sans / Mono (SIL OFL) |

Rebuild after token or style changes:

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --headless -s res://scripts/tools/build_cartel_theme.gd
```

## Viewport

`project.godot`:

- `1920×1080` design baseline
- `window/stretch/mode="canvas_items"`
- `window/stretch/aspect="expand"` — smaller windows scale down; extra pixels go to layout
- `gui/theme/custom="res://themes/cartel_theme.tres"`

## Design tokens (`Cartel` theme type)

Access in scenes/scripts:

```gdscript
get_theme_color("accent", "Cartel")
get_theme_constant("margin_md", "Cartel")
```

| Token | Hex | Use |
|-------|-----|-----|
| `bg` | `#0E1216` | Application background |
| `surface` | `#161C22` | Primary panel |
| `surface_alt` | `#1C242C` | Table header, toolbar |
| `elevated` | `#232C35` | Selected row, popups, focus |
| `border` | `#33404A` | 1px dividers |
| `text` | `#E4E2D8` | Primary text |
| `text_muted` | `#8A959E` | Secondary / metadata |
| `accent` | `#C9A227` | Actions, selected tab, focus |
| `positive` | `#3E8F73` | Success / online |
| `warning` | `#C9892E` | Degraded / caution |
| `negative` | `#C45C4A` | Fault / alert |
| `info` | `#5A7A94` | Informational (steel, not cyan) |

Spacing constants: `margin_sm` 8, `margin_md` 12, `list_row` 4, `separator` 1, `radius` 0–2px.

## Typography

| Variation | Font | Size |
|-----------|------|------|
| `Title` | Plex Sans Medium | 24 |
| `Headline` | Plex Sans Medium | 20 |
| `Section` | Plex Sans Medium | 15 (muted) |
| default `Label` | Plex Sans Regular | 15 |
| `Muted` | Plex Sans Regular | 14 |
| `Meta` | Plex Sans Regular | 12 |
| `Numeric` | Plex Mono Medium | 15 (accent) |
| `Alert` | Plex Sans Medium | 15 (negative) |
| `Positive` / `Warning` / `Negative` / `Info` | status colours | 15 |

Set on nodes: `theme_type_variation = &"Title"`.

## Panel variations

`PanelContainer` type variations:

- `Surface` — default operational panel
- `Elevated` — footer bars, selected contexts
- `Media` — editorial / art frames
- `Alert` — breaking strip with left status bar

## Operational vs media

One theme file; layout patterns distinguish modes:

- **Operational** — habitat, shipyard, HUD, menus: tables, metrics, compact buttons. Use `Surface`, `Numeric`, `Section`, `Muted`.
- **Media** — wire/headline layouts (showcase today): `Headline`, `Meta`, `Alert` banner. Same tokens, editorial hierarchy.

## Reusable patterns

Under `scenes/ui/patterns/` (native Controls only):

- `metric_block.tscn` — label + numeric value
- `status_row.tscn` — key / value row
- `headline_item.tscn` — headline + meta line
- `alert_banner.tscn` — compact alert strip
- `compact_toolbar.tscn` — button row
- `data_table.tscn` — header grid + ItemList

## Developer showcase

Static scene with System, Operational, and Media samples:

```bash
~/opt/Godot_v4.7.2-stable_linux.x86_64 --path /mnt/data/gitws/cartel2 \
  --scene res://scenes/dev/theme_showcase.tscn
```

Not the main scene — for visual QA and onboarding only.

## Conventions

- Prefer `theme_type_variation` over `theme_override_*` in scenes.
- Do not hardcode cyan/gold sci-fi colours in UI scripts.
- Dynamic labels: use `theme_type_variation = &"Section"` etc., or `get_theme_color()` for token lookups.
- HUD flight status sits in a compact top-left `Surface` panel when the ship has `basic_hud`. Sensor capabilities add a bottom-right local radar panel and viewport-edge waypoint arrows.
