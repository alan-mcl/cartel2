# Source-tag releases

Cartel ships as a **checked git tag** on this repository. There is no packaged binary exporter in-tree; `export_presets.cfg` stays local-only (gitignored). The labelled artefact is the tag plus the manifest printed by the release gate.

**GA scope** for the first numbered release is the current playable loop: Newtonian flight, habitat docking, commodity exchange, ship fitting at the yard, and passenger, freight, scan, and bounty charters (including volatile translations and hyperdrive route work where implemented today). Placeholder art and silent audio remain acceptable. Features listed under [not yet implemented](architecture.md#not-yet-implemented) are out of scope unless a release note explicitly says otherwise.

## Version identity

Two strings must always match:

| Location | Field |
|----------|--------|
| [`scripts/gameplay/game_version.gd`](../../../scripts/gameplay/game_version.gd) | `GameVersion.VERSION` (main menu ticker, save `game_version`) |
| [`project.godot`](../../../project.godot) | `config/version` |

Day-to-day development uses **`DEV`** in both places. A release commit sets both to `X.Y.Z` (first GA is `1.0.0`). After the tag, main returns both to `DEV` so the default branch never reads as a shipped build.

[`TestGameVersion`](../../../tests/test_game_version.gd) runs in [`./scripts/ci/check.sh`](../../../scripts/ci/check.sh) and asserts the two values stay aligned.

## Cut checklist

Run from a clean `main` (or the branch you intend to tag).

1. Set `GameVersion.VERSION` and `project.godot` `config/version` to `X.Y.Z`.
2. Add a section under [CHANGELOG.md](../../../CHANGELOG.md) for this version: what the loop includes, plus the [standing disclosures](#standing-disclosures) below (updated facts, not promises to fix them in the same cut).
3. For **1.0.0**, update the README **Status** paragraph to GA wording. For patch releases, adjust only if player-facing status changed. Leave README on early-development / `DEV` while main tracks development.
4. Commit the release bump and changelog entry.
5. Complete the [manual play checklist](#manual-play-checklist) once on that commit.
6. Run the automated gate:

   ```bash
   GODOT=/path/to/Godot ./scripts/ci/release_check.sh --version X.Y.Z
   ```

   The script requires a clean working tree, matching version strings (not `DEV`), and a full [`check.sh`](../../../scripts/ci/check.sh) pass. It prints a manifest (version, commit, Godot engine line, UTC timestamp).

7. Create an annotated tag: `git tag -a vX.Y.Z -m "Cartel X.Y.Z"`.
8. Push the tag only when asked.
9. On `main`, set both version strings back to `DEV` and commit.

Later, a Godot export step can sit after step 6 without changing the version rules above.

## Manual play checklist

The release gate cannot replace interactive verification. Before tagging, confirm on the release commit:

- **New Game** — Tester kit, docked at Proxima Habitat
- **Flight** — Undock, fly briefly, dock again
- **Exchange** — Buy and sell at least one commodity
- **Shipyard** — Fit or remove one module
- **Charter** — Accept one charter (any desk) and complete or abandon it
- **Save** — Save, quit to menu, load the same slot
- **Version line** — Main menu ticker opens with `Cartel 2, version 'X.Y.Z'`
- **Career death** — Hull destruction ends the career (overlay, matching save slot removed)

## Standing disclosures

Copy the current facts into each GA or patch note in CHANGELOG; adjust only when the underlying doc changes.

| Topic | Pointer |
|-------|---------|
| Placeholder art and silent audio | [asset_backlog.md](asset_backlog.md) |
| Not yet implemented | [architecture.md](architecture.md#not-yet-implemented) |
| Known bugs | [backlog.md](backlog.md) (for example bounty flee behaviour, Titania rings) |
| Save compatibility | Catalog module and ammunition ids are stored verbatim; renaming or removing a SKU invalidates old slots. Subsystem `version` migration under `subsystems` is the only automated save envelope migration. |
| Run requirements | Godot **4.7.2+**, GL Compatibility; check out git tag `vX.Y.Z` |
| Licences | [AGPL-3.0](../../../LICENSE); IBM Plex fonts under [SIL OFL 1.1](../../../assets/ui/fonts/LICENSE.txt) |

## Out of scope for this process

- Committed export presets or CI-built binaries
- Automatically fixing backlog bugs or replacing placeholders
- Save migrators for renamed catalog ids
- Pushing tags without an explicit request