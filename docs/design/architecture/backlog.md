# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

Implemented N-space transit, hazards, and per-N backdrops are documented in [n-space.md](../content/n-space.md) (flux, folds, shards, ascidian scan/sting/shed/fold/terrain flow). Do not edit frozen setting files for backlog items unless the request explicitly asks for setting-doc changes.

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B1| modules | low | per-chemistry fuel tank SKUs, and reactor fuel for fission and fusion plants.
|B2| UI | med | Leaderboard: "Tonnes" should say Freight, Career Time should be in in-game GST rather than player-time.
|B4| gameplay | low | ship sprites that appear/disappear from the HUD due to sensor range / stealth should fade in and out instead of winking

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F1|in flight|high| Unspace: infinite navigation within the play disc (or beyond), and broader randomised entry spawn plus exit-portal placement policy|
|F2|in flight|high| Sectors should support infinite lateral movement, just tiling background into infinity|
|F3|gameplay|high|Plotlines: longer duration sidequest-type content that the player can encounter, optional
|F9|HUD|med|provide a large-radar popup when clicking the minimap, full screen (no pause), extended range, more detail

