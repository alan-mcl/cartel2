# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

Implemented N-space transit, hazards, and per-N backdrops are documented in [n-space.md](../content/n-space.md) (flux, folds, shards, ascidian scan/sting/shed/fold/terrain flow). Do not edit frozen setting files for backlog items unless the request explicitly asks for setting-doc changes.

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B1| modules | low | per-chemistry fuel tank SKUs, and reactor fuel for fission and fusion plants.
|B2| art | med | Sail drive animation should be a semi-circle in front the of the ship ('n' shape), not a 'C' shape
|B4| art | high | parent body renderer should align the lighting to where the star is located in the sector
|B6| missions | med | bounty target "run away" behaviour isn't fun, should be reworked
|B7| ui | med | Need UI-friendly labels for module capabilities (e.g. "Habitat" instead of "ls_habitat")


## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F2|in flight|med| Unspace: infinite navigation within the play disc (or beyond), and broader randomised entry spawn plus exit-portal placement policy|
|F3|gameplay|med|Plotlines: implementations now that the framework is there
|F4|gameplay|med|Bar: add a "buy a round" button usable once per day that refreshes all the charters available, cost is proportional to system population from d50-d300
|F7|missions|med|New charter type: retrieval: go to a volatile location, retrieve something (requires a drone), return. Examples: Old Earth time capsule, jettisoned cargo, asteroid sample, etc|
F9|modules|med|Scatter cannon: tighten the spread and increase the range a bit|


