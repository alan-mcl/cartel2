# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

Implemented N-space transit, hazards, and per-N backdrops are documented in [n-space.md](../content/n-space.md) (flux, folds, shards, ascidian scan/sting/shed/fold/terrain flow). Do not edit frozen setting files for backlog items unless the request explicitly asks for setting-doc changes.

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B1| modules | low | per-chemistry fuel tank SKUs, and reactor fuel for fission and fusion plants.
|B2| art | med | Sail drive animation should be a semi-circle in front the of the ship ('n' shape), not a 'C' shape
|B3| art | med | no active sensors can't active-scan a target
|B4| art | high | parent body renderer should align the lighting to where the star is located in the sector

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F1|missions|med|Charters to include incentives for early finish, also include 7,8,9-space translations with scaled remuneration
|F2|in flight|med| Unspace: infinite navigation within the play disc (or beyond), and broader randomised entry spawn plus exit-portal placement policy|
|F3|gameplay|med|Plotlines: implementations now that the framework is there
|F5|UI|med|Ship module names to support the popup-info dialog on hover wherever they are (some places do not support this yet)


