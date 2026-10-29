# Agent guide - Cartel (Godot 4.7)

This repository is the **production Godot build** of Cartel, not a throwaway POC. Follow these conventions before finishing any change.

## Engine and run

- **Godot 4.7+**, GL Compatibility renderer
- Default binary: `~/opt/Godot_v4.7.2-stable_linux.x86_64` (override with `GODOT` env var)
- Run game: `GODOT=~/opt/Godot_v4.7.2-stable_linux.x86_64 $GODOT --path .` then F5, or see [README.md](README.md)
- Do **not** commit `.godot/` or editor user settings

## Architecture (read first)

| Layer | Path | Rules |
|-------|------|--------|
| Gameplay | `scripts/gameplay/` | `RefCounted` only - **no** scene tree, no `@onready` |
| Presentation | `scripts/presentation/` | Godot nodes, world loading, ship motion |
| UI | `scripts/ui/` | Menus, HUD, habitat/shipyard screens |
| Dev/tools | `scripts/dev/`, `scripts/tools/` | Sandboxes and one-off generators - not gameplay |

- Session state lives in **`GameSession`** (`scripts/gameplay/game_session.gd`), not `PrototypeSession`.
- `GameSession`'s forwarding properties are a compatibility facade. New code must use
  `session.player`, `session.world`, `session.fleet`, `session.wallet`, or `session.combat`
  directly; do not add forwarding properties.
- Content is JSON under `data/catalog/`. Frozen lore: `docs/setting/overview.md`, `corporations.md`, `planets.md`, `date_time.md`. Implementation docs are indexed from the root [README.md](README.md).
- **Those setting files are frozen** unless the user explicitly asks for a setting-doc change in that request. Do not edit them on your own, and do not invent lore in JSON to fill gaps they do not cover.
- Design docs describe what this repository implements today. When a change alters behaviour or catalog shape, update the doc that states it in the same change. `docs/design/architecture/` covers code layout, schemas, systems, and tooling (`architecture.md`, `data_model.md`, `commodity_economy.md`, `sprite_sizes.md`, `ui_theme.md`, `dev_sandboxes.md`). `docs/design/content/` covers playable rules and rosters (ships, equipment, commodities, trade network, translations, missions, field conditions, GST flow).
- Open work is tracked in [docs/design/architecture/backlog.md](docs/design/architecture/backlog.md). Items stay **Discuss** until picked up. Read **Do not** before starting. Remove the item in the same change as the work.
- **The project stays on GDScript.** A port to Godot .NET/C# was assessed and rejected. A language-bound hot loop, if one remains after algorithmic fixes, would be a GDExtension for that kernel.

## Required check before done

After any GDScript or catalog JSON change, run:

```bash
./scripts/ci/check.sh
```

Or with an explicit Godot path:

```bash
GODOT=~/opt/Godot_v4.7.2-stable_linux.x86_64 ./scripts/ci/check.sh
```

The script runs catalog validation, Godot import, a single-process parse sweep across `scripts/` and `tests/` ([`scripts/ci/check_scripts.gd`](scripts/ci/check_scripts.gd)), headless unit tests, and the scene smoke suite.

For the inner loop, `--fast` skips import, the parse sweep, and smokes (validators plus unit tests only). The unit suite includes balance metrics and can take a few minutes; `--scripts-only` and `--tests-only` run one half each. `--fast` is not sufficient to mark work complete - run the full check before you finish.

**Important:** Godot may exit `0` even when a script has parse errors. The check script scans output for `SCRIPT ERROR`, `Parse Error`, and `Failed to load script`. Do not claim compile-clean without running it.

Do **not** use `--check-only` with `--debug` (interactive debugger can hang).

## Writing tests

Gameplay is `RefCounted` with no scene-tree dependency, so it is testable headlessly without booting the game. Prefer adding a test over manual verification.

- Add a suite as `tests/test_<area>.gd` with `class_name Test<Area>` and a `static func run(runner: TestRunner)`, then register it in `tests/run.gd`.
- `TestRunner` offers `check(condition, label)` and `check_eq(actual, expected, label)`. Compare floats with a tolerance, not `check_eq`.
- Canonical examples: [tests/test_combat.gd](tests/test_combat.gd) and [tests/test_sensors.gd](tests/test_sensors.gd) for breadth, [tests/test_save.gd](tests/test_save.gd) for round-trip persistence.
- **Do not assert exact catalog counts.** Adding a SKU must never fail the suite; assert floors and structural invariants instead. See `_check_min_count` in [tests/test_catalog.gd](tests/test_catalog.gd).
- New `class_name` scripts are not visible to other scripts until an import pass runs, so run `./scripts/ci/check.sh` (or `--scripts-only`) rather than the test runner alone after adding a file.
- No GUT or gdUnit4 in this repo.

## Language

Use **British English** in setting docs, design prose, and player-facing catalog text (`description`, mission `text`, and similar). Keep American spellings only where required by Godot APIs, JSON keys, or stable catalog ids. See [.cursor/rules/british-english.mdc](.cursor/rules/british-english.mdc).

## GDScript conventions

- Typed GDScript 2.0; use existing `class_name` types (`Catalog`, `GameSession`, `OwnedShip`, …)
- Prefer `RefCounted` for gameplay logic; keep nodes thin
- Match naming: snake_case ids in JSON, PascalCase `class_name` in scripts
- No GUT/gdUnit4 in this repo - add tests under `tests/` using `TestRunner`

## Scope guardrails (unless explicitly asked)

- Only **4-space** Unspace is implemented; do not wire n>5 routes or hyperdrive translation without a plan
- Do not invent new setting canon in JSON alone. `docs/setting/overview.md`, `corporations.md`, `planets.md`, and `date_time.md` are frozen unless the user explicitly requests a setting-doc edit
- Merchants beyond Proxima Exchange remain partial; check README placeholders
- Do not unify the player and NPC simulation tick rate. Share the sim path; keep the cadences separate
- Do not pool projectiles
- Do not make `gdlint` mandatory
- `SaveStore.save_dir` is injectable. Tests must keep using a project-local directory. Do not write the default `user://saves/` slots from the suite

## Useful commands

```bash
# Create missing placeholder art (never replaces an existing file)
python3 scripts/tools/generate_placeholder_art.py

# Reimport assets
$GODOT --path . --headless --import --quit

# Rebuild UI theme
$GODOT --headless --path . --script res://scripts/tools/build_cartel_theme.gd

# Dev sandboxes (F6 in editor, or ./scripts/dev/<name>.sh) — see docs/design/architecture/dev_sandboxes.md
#   theme_showcase.sh  ship_assembly_sandbox.sh  combat_sandbox.sh
#   stealth_sandbox.sh  mission_harness.sh  system_render_tester.sh
```

## Documentation map

- [README.md](README.md) - run, controls, and the documentation index
- [docs/design/architecture/architecture.md](docs/design/architecture/architecture.md) - code layout and data flow
- [docs/design/architecture/data_model.md](docs/design/architecture/data_model.md) - catalog schemas and runtime types
- [docs/design/architecture/backlog.md](docs/design/architecture/backlog.md) - open design follow-ons
- Catalog files - `data/catalog/*.json`
