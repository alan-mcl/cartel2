# Dev sandboxes and harnesses

Interactive tools under `scenes/dev/` for iteration without the full career loop. In the editor, open a scene and press **F6** (Run Current Scene). From the repo root, use the launcher scripts below (they honour the `GODOT` env var, defaulting to `~/opt/Godot_v4.7.2-stable_linux.x86_64`).

Shared runner:

```bash
./scripts/dev/run_scene.sh res://scenes/dev/<scene>.tscn
```

| Launcher | Scene | Purpose |
|----------|-------|---------|
| [`scripts/dev/ship_assembly_sandbox.sh`](../../../scripts/dev/ship_assembly_sandbox.sh) | `ship_assembly_sandbox.tscn` | Fitting and engineering: drag modules, read budgets, no buy/sell loop |
| [`scripts/dev/combat_sandbox.sh`](../../../scripts/dev/combat_sandbox.sh) | `combat_sandbox.tscn` | 1v1 bout: pick hulls, attitude, pilot skill; **Esc** back to setup |
| [`scripts/dev/stealth_sandbox.sh`](../../../scripts/dev/stealth_sandbox.sh) | `stealth_sandbox.tscn` | Signature and detection drill with transponders off |
| [`scripts/dev/mission_harness.sh`](../../../scripts/dev/mission_harness.sh) | `mission_harness.tscn` | Volatile sites and scan/bounty objectives; **Begin** starts in-flight at the site; **F8** or pause quit reloads setup |
| [`scripts/dev/system_render_tester.sh`](../../../scripts/dev/system_render_tester.sh) | `system_render_tester.tscn` | Planetary layout and globe inspection (pan, zoom, frame) |
| [`scripts/dev/parent_body_harness.sh`](../../../scripts/dev/parent_body_harness.sh) | `parent_body_harness.tscn` | Procedural parent gas giant: atmosphere, orientation, legacy or multi-band rings (gaps, shadow, plane tilt); copy JSON for `worlds.json` |
| [`scripts/dev/theme_showcase.sh`](../../../scripts/dev/theme_showcase.sh) | `theme_showcase.tscn` | UI theme tokens and control variations |
| [`scripts/dev/audio_sandbox.sh`](../../../scripts/dev/audio_sandbox.sh) | `audio_sandbox.tscn` | Music, ambience, SFX, thrust, bus volumes, and positional collision |

Behaviour and architecture notes for each sandbox (except theme showcase) live in [architecture.md](architecture.md) under **Dev sandboxes** / **Mission harness** / **System render tester**. Theme tokens: [ui_theme.md](ui_theme.md).

Headless smoke coverage for several of these scenes is in [`scripts/dev/smoke_scenes.gd`](../../../scripts/dev/smoke_scenes.gd), invoked by `./scripts/ci/smoke_scenes.sh` as part of `./scripts/ci/check.sh`.
