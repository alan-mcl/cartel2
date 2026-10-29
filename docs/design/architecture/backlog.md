# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

Implemented N-space transit, hazards, and per-N backdrops are documented in [n-space.md](../content/n-space.md) (flux, folds, shards, ascidian scan/sting/shed/fold/terrain flow). Do not edit frozen setting files for backlog items unless the request explicitly asks for setting-doc changes.

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B1| modules | low | per-chemistry fuel tank SKUs, and reactor fuel for fission and fusion plants.
|B2| art | med | Sail drive animation should be a semi-circle in front the of the ship ('n' shape), not a 'C' shape
|B3| art | med | Lancer has no active sensors can't active-scan a target

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F1|in flight|high| Sectors should support infinite lateral movement, just tiling background into infinity|
|F2|in flight|high| Unspace: infinite navigation within the play disc (or beyond), and broader randomised entry spawn plus exit-portal placement policy|
|F3|gameplay|high|Plotlines: implementations now that the framework is there
