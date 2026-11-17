# Changelog

Cartel uses [semver](https://semver.org/) tags of the form `vX.Y.Z` on this repository. Development builds on `main` report in-game version **DEV**.

Release procedure: [docs/design/architecture/release.md](docs/design/architecture/release.md).

## Unreleased

Work in progress on `main` (`DEV`). See [README.md](README.md#project-status) for the current playable scope.

When cutting **1.0.0**, add a section below using this template (replace facts from the standing-disclosure table in `release.md` at cut time):

```markdown
## [1.0.0] - YYYY-MM-DD

### Scope

- Playable loop: flight, docking, commodity trade, ship fitting, charters (passenger, freight, scan, bounty), save/load (three slots), career death and hall of fame.

### Known limitations

- Placeholder art and silent audio per [asset backlog](docs/design/architecture/asset_backlog.md).
- Features not built per [architecture — not yet implemented](docs/design/architecture/architecture.md#not-yet-implemented).
- Open bugs per [backlog](docs/design/architecture/backlog.md).
- Saves store catalog ids verbatim; subsystem envelope versioning only for registered subsystems.
- Requires Godot 4.7.2+ and this source tag; AGPL-3.0 plus SIL OFL for bundled fonts.
```