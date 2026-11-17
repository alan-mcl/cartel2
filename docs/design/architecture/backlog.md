# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

Implemented N-space transit, hazards, and per-N backdrops are documented in [n-space.md](../content/n-space.md) (flux, folds, shards, ascidian scan/sting/shed/fold/terrain flow). Do not edit frozen setting files for backlog items unless the request explicitly asks for setting-doc changes.

Content features F3, F10, and F2 stay in the feature table; entity spawn registration and the traffic query split are landed (F3 desk and F10 escape-hook wiring are landed). November 2026 refactoring items R2–R15 are closed.

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B6 | missions | med | bounty target "run away" behaviour isn't fun, should be reworked |
|B1|data|med|Double 'Janus' in the planets catalog|

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F3|gameplay|med|Plotlines: authored arc content in `plotlines.json` now that desk wiring is landed|
|F9|modules|med|Scatter cannon: tighten the spread and increase the range a bit|
|F10|npc|med|NPC pilots to use hyperdrives if equipped (escape notification is in gameplay)|
|F1|art|low|irregularly shaped planet renderer (for comets, KBOs, etc)|
|F2|systems|med|asteroid/debris placement around maps and vectors (entity spawn registration is landed)|

## Addenda

### Unused celebrity pilot and ship names

Cuno - Doomed Commercial Venture
The Accountant
Public Enemy
Xenocyte
Marty - Easy Street
Sledge
Lunchbox
Zenith

Ladbroke Grove
Long On Gravitas
Paper Tiger
Any Given Sunday
No Future
Unfinished Business
Kodak Moment
Glory to Arstotzka
Tannhäuser Gate
Nothing Personal
Terms and Conditions
Unscheduled Maintenance
No Fixed Solution
End All Wars
A Distant Memory
No Quarter
Second Chance
Bad Habit
One More Time
Critical Path
Zero Defects
Southern Cross


