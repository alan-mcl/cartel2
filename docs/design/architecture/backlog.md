# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

Implemented N-space transit, hazards, and per-N backdrops are documented in [n-space.md](../content/n-space.md) (flux, folds, shards, ascidian scan/sting/shed/fold/terrain flow). Do not edit frozen setting files for backlog items unless the request explicitly asks for setting-doc changes.

**Refactoring** items (R2–R15) are structural debt from the November 2026 review. Pick one id at a time. Read **Depends on** and **Do not** before editing. Content features F3, F10, and F2 stay in the feature table; entity spawn registration and the traffic query split are landed (F3 desk and F10 escape-hook wiring are landed).

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B6 | missions | med | bounty target "run away" behaviour isn't fun, should be reworked |
|B1|data|med|Double 'Janus' in the planets catalog|
|B2|ui|med|'pay sanctions' button doesn't turn into 'launch' when you have no more sanctions until you change buildings away then back|
|B3|missions|med|Could accept a 'biohazard' charter with a non-biohazard hold?|

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F3|gameplay|med|Plotlines: authored arc content in `plotlines.json` now that desk wiring is landed|
|F9|modules|med|Scatter cannon: tighten the spread and increase the range a bit|
|F10|npc|med|NPC pilots to use hyperdrives if equipped (escape notification is in gameplay)|
|F1|art|low|irregularly shaped planet renderer (for comets, KBOs, etc)|
|F2|systems|med|asteroid/debris placement around maps and vectors (entity spawn registration is landed)|

## Refactoring

Structural work only. R9, R10, and R12 can land any time.

| ID | Area | Sev | Desc |
|----|------|-----|------|
|R9|data|med|Hand-authored catalog content stays CI-safe|
|R10|data|med|One chassis source on AssembledShip; typed getters stop rebuilding dictionaries|
|R12|ui|med|One soft-refresh helper for the dock desks|

### R9 — Hand-authored catalog content stays CI-safe

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/tools/validate_catalog_refs.py` and any follow-on catalog tooling. Targets: `worlds.json`, `buildings.json`, `traffic.json`, `interactables.json`
- **Do not:** add unknown-key allowlists, `additionalProperties` schemas, or new broken-reference failures that reject a new field, record, or in-progress id in those four files; generate `*Def` classes for missions, plotlines, or encounters; convert gameplay readers off dictionaries
- **Acceptance:** those four files remain open for hand-edited content. CI must not fail solely because a new key, record, or unwired id appears. Existing validators stay; this item does not add stricter gates.

### R10 — Typed chassis access

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/gameplay/catalog.gd` dictionary getters that `to_dict()` a record, `scripts/gameplay/assembled_ship.gd`
- **Do not:** type buildings, worlds, or missions; change fitting rules
- **Acceptance:** `AssembledShip` has one chassis source of truth. Gameplay reads `get_*_def` for types that already have a record. Dictionary copies happen at a library or UI boundary, not on every lookup. Assembler and catalog tests pass.

### R12 — Shared dock soft-refresh

- **Status:** Discuss
- **Depends on:** —
- **Scope:** `scripts/ui/market_panel.gd`, `scripts/ui/dealer_panel.gd`, `scripts/ui/terminal_panel.gd`, `scripts/ui/shipyard_screen.gd`, `scripts/ui/corporate_office_panel.gd`, `scripts/ui/habitat_screen.gd`, `scripts/ui/ui_patterns.gd` or a neighbour
- **Do not:** redesign the desks; change prices, fitting, or charter acceptance
- **Acceptance:** soft refresh, meta-host lookup, and select-by-id live in one helper used by those desks. One `session.changed` refreshes an embedded habitat panel once. The `session.visit` re-entry guard still prevents a recursive rebuild.

## Addenda

### Unused celebrity pilot and ship names

Cuno - Doomed Commercial Venture
The Accountant
Public Enemy
Xenocyte
Marty - Easy Street

Ladbroke Grove
Long On Gravitas
Paper Tiger
Any Given Sunday
No Future
Unfinished Business
Kodak Moment
Glory to Arstotzka

