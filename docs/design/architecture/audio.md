# Audio

Presentation-layer audio for Cartel: global music and ambience, logical sound identifiers, bus mixing, and settings stored outside save slots. Gameplay `RefCounted` code does not reference asset paths or `AudioStreamPlayer` nodes.

## Autoload and buses

**AudioManager** (`scripts/presentation/audio/audio_manager.gd`) is an autoload singleton. It owns stream players, crossfades, the SFX pool, ship engine loop, and bus volume application.

Bus layout: [`audio/default_bus_layout.tres`](../../../audio/default_bus_layout.tres)

| Bus | Role |
|-----|------|
| Master | Overall level |
| Music | Context music |
| SFX | Gameplay one-shots and ship engine |
| Ambience | Environmental loops |
| UI | Interface feedback |

User volume sliders write bus levels via `AudioServer`; individual players are not scaled for settings.

## Logical identifiers

[`data/audio/library.json`](../../../data/audio/library.json) maps:

- **Music contexts** — `menu`, `exploration`, `habitat`, `shipyard`, `market`, `danger` → one or more OGG paths (v1 plays the first track).
- **Ambience contexts** — `space`, `habitat`, …
- **SFX ids** — dotted names such as `ui.click`, `ship.collision`, `interaction.salvage`, `ship.thruster` (loop).

Callers use [`AudioService`](../../../scripts/presentation/audio/audio_service.gd) static methods (`play_music("habitat")`, `play_sfx("interaction.salvage")`, `play_ui("click")`, and so on), which delegate to the autoload at runtime. Catalog JSON may gain optional `audio` fields later using the same ids; this pass does not add them.

Resolution and variant selection live in [`scripts/presentation/audio/audio_library.gd`](../../../scripts/presentation/audio/audio_library.gd).

## Settings persistence

[`scripts/presentation/audio/audio_settings.gd`](../../../scripts/presentation/audio/audio_settings.gd) stores linear 0.0–1.0 levels in `user://settings/settings.json` (`version` + `audio` object). A legacy `user://settings.json` file is still read once if present. Tests override `AudioSettings.settings_path`. This file is independent of `user://saves/`.

The **Audio** entry on the main menu and pause overlay opens [`scripts/ui/audio_settings_panel.gd`](../../../scripts/ui/audio_settings_panel.gd) (five sliders: master, music, SFX, ambience, UI).

## Scene integration

| Moment | Audio |
|--------|--------|
| Main menu | `menu` music; ambience stopped |
| In-flight space | `exploration` + `space` ambience |
| Docked habitat UI | `habitat` music and ambience; engine thrust cleared |
| Undock | Return to exploration / space |
| Salvage success | Positional `interaction.salvage` |
| Hull slide collision | Positional `ship.collision` (rate-limited) |
| Ship thrust | Loop `ship.thruster` driven by normalized thrust and boost |

Positional playback uses `AudioStreamPlayer2D` on the autoload; listening uses an `AudioListener2D` on **FollowCamera**.

Process modes: music, ambience, and UI players use `PROCESS_MODE_ALWAYS` so they continue under pause; SFX, positional SFX, and the engine loop use `PROCESS_MODE_PAUSABLE`.

## Assets

Shipped audio is **OGG Vorbis** under `assets/audio/` (`music/`, `ambience/`, `sfx/`). **Music and ambience** placeholders from [`scripts/tools/generate_placeholder_audio.py`](../../../scripts/tools/generate_placeholder_audio.py) are silent loops (the script skips `music/menu/menu_01.ogg` when regenerating). **UI and SFX** placeholders are short dry tones from the same script. Replace files with production assets without changing logical ids.

## Dev sandbox

[`scripts/dev/audio_sandbox.sh`](../../../scripts/dev/audio_sandbox.sh) → `scenes/dev/audio_sandbox.tscn` — music and ambience contexts, SFX triggers, thrust slider, positional collision test, and volume panel. Listed in [dev_sandboxes.md](dev_sandboxes.md).

## Web and export

The stack uses Godot’s standard streams and buses only (no middleware). Browsers may block audio until the first user gesture; menu and sandbox buttons satisfy that. On application focus-in, bus volumes are reapplied.

**Export verification:** headless CI does not listen to audio. Manual checks: run the audio sandbox on desktop; run a Web export if Godot export templates are installed locally and confirm the sandbox plays after a click. No export presets are committed in this repository; document local export results when you run them.

## Tests

[`tests/test_audio.gd`](../../../tests/test_audio.gd) covers library resolution, settings round-trip, volume curve, and context or rate-limit gates (`AudioGates`).
