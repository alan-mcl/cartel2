# Agent guide — Cartel (Godot 4.7)

This repository is the **production Godot build** of Cartel, not a throwaway POC. Follow these conventions before finishing any change.

## Engine and run

- **Godot 4.7+**, GL Compatibility renderer
- Default binary: `~/opt/Godot_v4.7.2-stable_linux.x86_64` (override with `GODOT` env var)
- Run game: `GODOT=~/opt/Godot_v4.7.2-stable_linux.x86_64 $GODOT --path .` then F5, or see [README.md](README.md)
- Do **not** commit `.godot/` or editor user settings

## Architecture (read first)

| Layer | Path | Rules |
|-------|------|--------|
| Gameplay | `scripts/gameplay/` | `RefCounted` only — **no** scene tree, no `@onready` |
| Presentation | `scripts/presentation/` | Godot nodes, world loading, ship motion |
| UI | `scripts/ui/` | Menus, HUD, habitat/shipyard screens |
| Dev/tools | `scripts/dev/`, `scripts/tools/` | Sandboxes and one-off generators — not gameplay |

- Session state lives in **`GameSession`** (`scripts/gameplay/game_session.gd`), not `PrototypeSession`.
- Content is JSON under `data/catalog/`. Lore and design intent: [docs/setting/](docs/setting/README.md). Implementation notes: [docs/design/architecture.md](docs/design/architecture.md).
- **Setting before JSON:** edit setting docs when changing lore; then update catalogs to match.
- Planned refactors are tracked as pickable work items in [docs/design/refactor_backlog.md](docs/design/refactor_backlog.md). Read the item's **Depends on** and **Explicitly do NOT** before starting, and update its **Status** in the same commit.
- **The project stays on GDScript.** A port to Godot .NET/C# was assessed and rejected; see the standing decision in the refactor backlog before proposing one.

## Required check before done

After any GDScript or catalog JSON change, run:

```bash
./scripts/ci/check.sh
```

Or with an explicit Godot path:

```bash
GODOT=~/opt/Godot_v4.7.2-stable_linux.x86_64 ./scripts/ci/check.sh
```

The script runs catalog validation, Godot import, `--check-only` across `scripts/` and `tests/`, and headless unit tests.

For the inner loop, `--fast` skips the import and parse sweep (validators plus unit tests, a few seconds); `--scripts-only` and `--tests-only` run one half each. `--fast` is not sufficient to mark work complete — run the full check before you finish. The parse sweep parallelises over `nproc`; use `--jobs N` to change that.

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

## GDScript conventions

- Typed GDScript 2.0; use existing `class_name` types (`Catalog`, `GameSession`, `OwnedShip`, …)
- Prefer `RefCounted` for gameplay logic; keep nodes thin
- Match naming: snake_case ids in JSON, PascalCase `class_name` in scripts
- No GUT/gdUnit4 in this repo — add tests under `tests/` using `TestRunner`

## Scope guardrails (unless explicitly asked)

- Only **4-space** Unspace is implemented; do not wire n>5 routes or hyperdrive translation without a plan
- Do not invent new setting canon in JSON alone — update `docs/setting/` first
- Merchants beyond Proxima Exchange remain partial; check README placeholders

## Useful commands

```bash
# Regenerate placeholder art
python3 scripts/tools/generate_placeholder_art.py

# Reimport assets
$GODOT --path . --headless --import --quit

# Rebuild UI theme
$GODOT --headless --path . --script res://scripts/tools/build_cartel_theme.gd

# Theme showcase (F6 in editor)
# res://scenes/dev/theme_showcase.tscn

# Ship assembly sandbox (F6)
# res://scenes/dev/ship_assembly_sandbox.tscn

# Combat sandbox (F6)
# res://scenes/dev/combat_sandbox.tscn

# Stealth sandbox (F6)
# res://scenes/dev/stealth_sandbox.tscn
```

## Documentation map

- [README.md](README.md) — run, controls, loop
- [docs/README.md](docs/README.md) — design vs setting index
- [docs/design/architecture.md](docs/design/architecture.md) — code layout and data flow
- [docs/design/data_model.md](docs/design/data_model.md) — catalog schemas and runtime types
- [docs/design/refactor_backlog.md](docs/design/refactor_backlog.md) — phased engineering work items
- Catalog files — `data/catalog/*.json`
