# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B1| modules | low | per-chemistry fuel tank SKUs, and reactor fuel for fission and fusion plants.
|B2| UI | med | Leaderboard: "Tonnes" should say Freight, Career Time should be in in-game GST rather than player-time.
|B4| gameplay | low | ship sprites that appear/disappear from the HUD due to sensor range / stealth should fade in and out instead of winking

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F1|in flight|high| Build out the unspace implementation: 9 layers, hazards, hull stress, asciidian sprites and behaviour, infinite unspace nav, player and exit portal placement random|
|F2|in flight|high| Sectors should support infinite lateral movement, just tiling background into infinity|


